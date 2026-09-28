// LoopFollow
// BasalProfile.swift

import CryptoKit
import Foundation

/// A named basal schedule kept on this phone: 24 hourly rates (U/h). Sent to Trio with `set_basal_schedule`.
struct BasalProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    /// Exactly 24 values, index = hour of day.
    var hourlyRates: [Decimal]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, hourlyRates: [Decimal], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.hourlyRates = hourlyRates
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Changes to the saved list. Every profile keeps its id: screens are opened by id, so an id that changed on a
/// write would close them.
enum BasalProfileList {
    /// Replaces the profile with the same id, or appends it; no other element is touched.
    static func upsert(_ profile: BasalProfile, into list: [BasalProfile], now: Date = Date()) -> [BasalProfile] {
        var list = list
        var updated = profile
        updated.updatedAt = now
        if let i = list.firstIndex(where: { $0.id == profile.id }) { list[i] = updated } else { list.append(updated) }
        return list
    }

    static func profile(id: UUID, in list: [BasalProfile]) -> BasalProfile? {
        list.first { $0.id == id }
    }
}

/// One segment of the `basal_schedule` array Trio accepts (Trio `RemoteBasalSchedule.Segment`).
struct BasalScheduleSegment: Codable, Equatable {
    let start: String // "HH:00"
    let rate: Decimal // U/h
}

/// Pure rules shared with Trio (vidasrimkus/Trio CUSTOMIZATIONS.md §7): segments, hash, daily total and the
/// validation Trio repeats. No storage or network here, so all of it is unit-tested.
enum BasalProfileMath {
    static let maxNameLength = 30
    static let hours = 24

    // MARK: Segments

    /// Adjacent hours with the same rate merged into one segment, starting at 00:00.
    static func segments(_ hourly: [Decimal]) -> [BasalScheduleSegment] {
        var result: [BasalScheduleSegment] = []
        var last: Decimal?
        for (hour, rate) in hourly.enumerated() where rate != last {
            result.append(BasalScheduleSegment(start: String(format: "%02d:00", hour), rate: rate))
            last = rate
        }
        return result
    }

    /// 24 hourly rates from a Nightscout basal schedule (`timeAsSeconds`, `value`), or nil when a segment does not
    /// start on a whole hour or the schedule does not start at 00:00 (it cannot be represented exactly).
    static func hourly(fromNightscout entries: [(seconds: Int, rate: Double)]) -> [Decimal]? {
        let sorted = entries.sorted { $0.seconds < $1.seconds }
        guard let first = sorted.first, first.seconds == 0 else { return nil }
        guard sorted.allSatisfy({ $0.seconds % 3600 == 0 && $0.seconds < 24 * 3600 }) else { return nil }
        var hourly: [Decimal] = []
        for hour in 0 ..< hours {
            let rate = sorted.last(where: { $0.seconds <= hour * 3600 })!.rate
            hourly.append(Decimal(cents(fromDouble: rate)) / 100)
        }
        return hourly
    }

    // MARK: Hash (identical to Trio RemoteBasalSchedule.hash — Trio CUSTOMIZATIONS.md §7)

    /// The rate in force at each of the 48 half-hours 00:00 … 23:30, in whole hundredths: the entry with the
    /// latest start at or before that minute; before the first entry, the last entry (a daily schedule wraps).
    static func halfHourSlots(_ entries: [(minutes: Int, cents: Int)]) -> [Int] {
        let sorted = entries.sorted { $0.minutes < $1.minutes }
        guard let last = sorted.last else { return [] }
        return (0 ..< 48).map { slot in (sorted.last(where: { $0.minutes <= slot * 30 }) ?? last).cents }
    }

    /// The 48 half-hour values joined with ";"; hash = lowercase hex of the first 8 bytes of SHA-256 over the
    /// UTF-8 bytes. Depends on what the schedule delivers, not on how it is split into entries.
    static func hash(entries: [(minutes: Int, cents: Int)]) -> String {
        let canonical = halfHourSlots(entries).map(String.init).joined(separator: ";")
        return SHA256.hash(data: Data(canonical.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Hash of a profile's 24 hourly rates.
    static func hash(ofHourly hourly: [Decimal]) -> String {
        hash(entries: hourly.enumerated().map { (minutes: $0.offset * 60, cents: roundedCents($0.element)) })
    }

    /// Hash of the schedule this app would send (merged segments) — equal to `hash(ofHourly:)` of the same rates.
    static func hash(ofSegments segments: [BasalScheduleSegment]) -> String {
        hash(entries: segments.map { (minutes: (Int($0.start.prefix(2)) ?? 0) * 60, cents: roundedCents($0.rate)) })
    }

    /// Hash of Trio's active schedule as Nightscout shows it (any split, including 30-minute segments).
    /// This is the value for `expected_active_hash`.
    static func hash(ofNightscout entries: [(seconds: Int, rate: Double)]) -> String {
        hash(entries: entries.map { (minutes: $0.seconds / 60, cents: cents(fromDouble: $0.rate)) })
    }

    // MARK: Totals

    static func dailyTotal(_ hourly: [Decimal]) -> Decimal {
        hourly.reduce(0, +)
    }

    /// Relative change in percent (rounded to a whole number); nil when the old total is 0.
    static func percentChange(from old: Decimal, to new: Decimal) -> Int? {
        guard old != 0 else { return nil }
        let value = NSDecimalNumber(decimal: (new - old) / old * 100).doubleValue
        return Int(value.rounded())
    }

    // MARK: Validation (the same rules Trio applies; Trio stays the authority)

    enum Problem: Equatable {
        case name(String)
        case hour(Int, String)

        var text: String {
            switch self {
            case let .name(text): return text
            case let .hour(hour, text): return String(format: "%02d:00 — ", hour) + text
            }
        }
    }

    static func validate(name: String, hourly: [Decimal]) -> [Problem] {
        var problems: [Problem] = []
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.count > maxNameLength {
            problems.append(.name("Pavadinimas turi būti 1–\(maxNameLength) simbolių."))
        } else if trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0 == "\"" }) {
            problems.append(.name("Pavadinime negali būti kabučių ar valdymo simbolių."))
        }
        guard hourly.count == hours else {
            return problems + [.name("Turi būti lygiai 24 valandos.")]
        }
        for (hour, rate) in hourly.enumerated() {
            if rate <= 0 {
                problems.append(.hour(hour, "turi būti daugiau nei 0 U/h."))
            } else if exactCents(rate) == nil {
                problems.append(.hour(hour, "tik 0.01 U/h tikslumu."))
            } else if danaStoredCents(rate) != exactCents(rate) {
                let near = nearestExact(rate).map { "\($0)" }.joined(separator: " arba ")
                problems.append(.hour(hour, "Dana išsaugotų kitą reikšmę. Rinkitės \(near) U/h."))
            }
        }
        return problems
    }

    /// Hundredths when the rate is a whole number of hundredths, else nil.
    static func exactCents(_ rate: Decimal) -> Int? {
        var scaled = rate * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard rounded == scaled else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// What a Dana stores for this rate on Trio's path: Decimal → Double(truncating:) → UInt16(value * 100).
    static func danaStoredCents(_ rate: Decimal) -> Int {
        Int(UInt16(Double(truncating: rate as NSNumber) * 100))
    }

    /// The closest rates (0.01 steps, below and above) the Dana stores exactly.
    static func nearestExact(_ rate: Decimal) -> [Decimal] {
        guard let cents = exactCents(rate) else { return [] }
        var result: [Decimal] = []
        for direction in [-1, 1] {
            var candidate = cents + direction
            while candidate > 0, candidate < cents + 100 {
                let value = Decimal(candidate) / 100
                if danaStoredCents(value) == candidate { result.append(value); break }
                candidate += direction
            }
        }
        return result
    }

    private static func roundedCents(_ rate: Decimal) -> Int {
        var scaled = rate * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    private static func cents(fromDouble rate: Double) -> Int {
        Int((rate * 100).rounded())
    }
}
