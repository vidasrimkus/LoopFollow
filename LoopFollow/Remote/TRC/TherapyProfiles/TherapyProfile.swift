// LoopFollow
// TherapyProfile.swift

import CryptoKit
import Foundation

/// Carb ratio or ISF. The two are separate lists, separate commands (`set_carb_ratios`, `set_isf`) and separate
/// screens; they share the rules below (contract cr-isf: 30-minute grid, 48 half-hour slots, hashes).
enum TherapyKind: String, Codable, CaseIterable {
    case carbRatio
    case isf
}

/// One schedule entry in the stored unit: CR in tenths of g/U (85 = 8.5 g/U), ISF in whole mg/dL (always, whatever
/// unit the app shows).
struct TherapyEntry: Codable, Equatable {
    /// Start minute of the day, a multiple of 30.
    var minutes: Int
    var value: Int
}

/// A named CR or ISF schedule kept on this phone.
struct TherapyProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: TherapyKind
    var name: String
    var entries: [TherapyEntry]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), kind: TherapyKind, name: String, entries: [TherapyEntry], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.name = name
        self.entries = entries
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// `carb_ratio_schedule` entry (contract: `{"start":"HH:MM","ratio":<g/U>}`).
struct CarbRatioScheduleEntry: Codable, Equatable {
    let start: String
    let ratio: Decimal
}

/// `isf_schedule` entry (contract: `{"start":"HH:MM","sensitivity":<integer mg/dL>}`).
struct ISFScheduleEntry: Codable, Equatable {
    let start: String
    let sensitivity: Int
}

/// Changes to a saved list; every profile keeps its id (screens are opened by id).
enum TherapyProfileList {
    static func upsert(_ profile: TherapyProfile, into list: [TherapyProfile], now: Date = Date()) -> [TherapyProfile] {
        var list = list
        var updated = profile
        updated.updatedAt = now
        if let i = list.firstIndex(where: { $0.id == profile.id }) { list[i] = updated } else { list.append(updated) }
        return list
    }

    static func profile(id: UUID, in list: [TherapyProfile]) -> TherapyProfile? {
        list.first { $0.id == id }
    }
}

/// Which saved profile is "the active one" — the same rules as `BasalActiveMarker`: identity from the stored active
/// id, ✓ only while that profile's hash equals Nightscout's. The hash is the Nightscout form (for ISF it depends on
/// the units Trio uploads in), so `nsMgdl` is passed along.
enum TherapyActiveMarker {
    enum RowState: Equatable {
        case active
        case matchesActive
        case none
    }

    private static func matches(_ profile: TherapyProfile, nsHash: String?, nsMgdl: Bool) -> Bool {
        guard let nsHash else { return false }
        return TherapyProfileMath.nightscoutFormHash(profile.entries, kind: profile.kind, nsMgdl: nsMgdl) == nsHash
    }

    static func rowState(_ profile: TherapyProfile, activeID: UUID?, nsHash: String?, nsMgdl: Bool) -> RowState {
        guard matches(profile, nsHash: nsHash, nsMgdl: nsMgdl) else { return .none }
        return profile.id == activeID ? .active : .matchesActive
    }

    static func canDelete(_ profile: TherapyProfile, activeID: UUID?) -> Bool {
        profile.id != activeID
    }

    static func noSavedMatch(_ profiles: [TherapyProfile], nsHash: String?, nsMgdl: Bool) -> Bool {
        guard nsHash != nil else { return false }
        return !profiles.contains { matches($0, nsHash: nsHash, nsMgdl: nsMgdl) }
    }

    static func matchingProfile(_ profiles: [TherapyProfile], activeID: UUID?, nsHash: String?, nsMgdl: Bool) -> TherapyProfile? {
        let found = profiles.filter { matches($0, nsHash: nsHash, nsMgdl: nsMgdl) }
        return found.first { $0.id == activeID } ?? found.min { $0.createdAt < $1.createdAt }
    }

    static func afterActivation(sent profileID: UUID, success: Bool, current: UUID?) -> UUID? {
        success ? profileID : current
    }

    static func initialActiveID(_ profiles: [TherapyProfile], storedID: UUID?, nsHash: String?, nsMgdl: Bool) -> UUID? {
        if let storedID, profiles.contains(where: { $0.id == storedID }) { return storedID }
        guard nsHash != nil else { return storedID }
        return profiles
            .filter { matches($0, nsHash: nsHash, nsMgdl: nsMgdl) }
            .min { $0.createdAt < $1.createdAt }?.id ?? storedID
    }
}

/// Pure rules shared with Trio (contract cr-isf). No storage or network here, so all of it is unit-tested.
enum TherapyProfileMath {
    static let maxNameLength = 30
    static let slotCount = 48
    static let maxEntries = 48
    /// CR in tenths of g/U: 1.0 … 50.0.
    static let crTenthsRange = 10 ... 500
    /// ISF in mg/dL: 9 … 540.
    static let isfMgdlRange = 9 ... 540

    // MARK: Slots and hashes

    /// The value in force at each of the 48 half-hours: the entry with the latest start ≤ that minute; before the
    /// first entry, the last entry (daily wrap).
    static func slots(_ entries: [TherapyEntry]) -> [Int] {
        let sorted = entries.sorted { $0.minutes < $1.minutes }
        guard let last = sorted.last else { return [] }
        return (0 ..< slotCount).map { slot in (sorted.last(where: { $0.minutes <= slot * 30 }) ?? last).value }
    }

    /// Lowercase hex of the first 8 bytes of SHA-256 over `prefix;v0;v1;…;v47`.
    static func hash(prefix: String, slots: [Int]) -> String {
        let canonical = ([prefix] + slots.map(String.init)).joined(separator: ";")
        return SHA256.hash(data: Data(canonical.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func crHash(tenths slots: [Int]) -> String { hash(prefix: "cr", slots: slots) }
    static func isfMgdlHash(_ slots: [Int]) -> String { hash(prefix: "isf-mgdl", slots: slots) }
    static func isfMmolHash(tenths slots: [Int]) -> String { hash(prefix: "isf-mmol", slots: slots) }

    /// The 48 integers Nightscout shows for these stored entries: CR tenths; ISF mg/dL, or — when Trio uploads in
    /// mmol/L — tenths of `asMmolL(mg/dL)`.
    static func nightscoutFormSlots(_ entries: [TherapyEntry], kind: TherapyKind, nsMgdl: Bool) -> [Int] {
        let exact = slots(entries)
        guard kind == .isf, !nsMgdl else { return exact }
        return exact.map(mmolTenths(mgdl:))
    }

    static func nightscoutFormHash(_ entries: [TherapyEntry], kind: TherapyKind, nsMgdl: Bool) -> String {
        hash(kind: kind, nsMgdl: nsMgdl, nightscoutSlots: nightscoutFormSlots(entries, kind: kind, nsMgdl: nsMgdl))
    }

    /// Hash of Nightscout-form slots; this is `expected_active_hash`.
    static func hash(kind: TherapyKind, nsMgdl: Bool, nightscoutSlots slots: [Int]) -> String {
        switch kind {
        case .carbRatio: return crHash(tenths: slots)
        case .isf: return nsMgdl ? isfMgdlHash(slots) : isfMmolHash(tenths: slots)
        }
    }

    // MARK: Units

    /// Trio `asMmolL` = round(mg/dL × 0.0555, 1 decimal, half-up), returned in tenths. Exact integer arithmetic:
    /// mg/dL × 0.555 = mg/dL × 555 / 1000.
    static func mmolTenths(mgdl: Int) -> Int {
        (mgdl * 555 + 500) / 1000
    }

    /// mmol/L (tenths) → mg/dL (contract, revised): the SMALLEST m in 9…540 with `asMmolL(m) == x` — the value Trio's
    /// own mmol/L ISF editor stores (DecimalPickerSettings.swift:22-28); nil when none.
    static func mgdl(fromMmolTenths tenths: Int) -> Int? {
        isfMgdlRange.first { mmolTenths(mgdl: $0) == tenths }
    }

    /// The mg/dL Trio's mmol/L ISF editor would keep for `mgdl`: the smallest of its 0.1 mmol/L group. When Trio runs in
    /// mmol/L, `set_isf` refuses any other value.
    static func trioMmolEditorValue(mgdl: Int) -> Int {
        mgdl(fromMmolTenths: mmolTenths(mgdl: mgdl)) ?? mgdl
    }

    /// Entries as they may be sent: with Trio in mmol/L every ISF value is snapped to the smallest mg/dL of its
    /// 0.1 mmol/L group (same Nightscout form, so the hash and the ✓ do not change), with a note per changed entry.
    static func snappedForTrio(_ entries: [TherapyEntry], kind: TherapyKind, trioMmol: Bool) -> (entries: [TherapyEntry], notes: [String]) {
        guard kind == .isf, trioMmol else { return (entries, []) }
        var notes: [String] = []
        let snapped = entries.map { entry -> TherapyEntry in
            let value = trioMmolEditorValue(mgdl: entry.value)
            if value != entry.value {
                notes.append("\(clock(entry.minutes)): \(entry.value) → bus siunčiama \(value) mg/dL — Trio mmol/L redaktoriaus reikšmė.")
            }
            return TherapyEntry(minutes: entry.minutes, value: value)
        }
        return (snapped, notes)
    }

    /// Round half-up of `value × scale` computed in decimal from the shortest text of the Double (so 1.15 is 1.15,
    /// not 1.149999…), as Nightscout/JSON shows the number.
    static func roundedHalfUp(_ value: Double, scale: Int) -> Int {
        var scaled = (Decimal(string: "\(value)", locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)) * Decimal(scale)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    // MARK: Nightscout

    /// Nightscout entries (`timeAsSeconds`, `value`) → the integers the hash is computed from: CR ratio × 10; ISF
    /// value × 10 when the profile is in mmol/L, else the mg/dL value; each rounded half-up.
    static func nightscoutValues(_ entries: [(seconds: Int, value: Double)], kind: TherapyKind, nsMgdl: Bool) -> [TherapyEntry] {
        let scale = kind == .isf && nsMgdl ? 1 : 10
        return entries.map { TherapyEntry(minutes: $0.seconds / 60, value: roundedHalfUp($0.value, scale: scale)) }
    }

    static func nightscoutSlots(_ entries: [(seconds: Int, value: Double)], kind: TherapyKind, nsMgdl: Bool) -> [Int] {
        slots(nightscoutValues(entries, kind: kind, nsMgdl: nsMgdl))
    }

    static func nightscoutHash(_ entries: [(seconds: Int, value: Double)], kind: TherapyKind, nsMgdl: Bool) -> String? {
        entries.isEmpty ? nil : hash(kind: kind, nsMgdl: nsMgdl, nightscoutSlots: nightscoutSlots(entries, kind: kind, nsMgdl: nsMgdl))
    }

    /// Stored-unit entries from Nightscout's schedule, for "Išsaugoti dabartinį kaip…" and "Ankstesnis". nil when a
    /// start is off the 30-minute grid, the schedule does not start at 00:00, or a value is out of range. ISF shown
    /// in mmol/L is turned back into mg/dL with `mgdl(fromMmolTenths:)` (the smallest of its group, what Trio's mmol/L
    /// editor stores) — it shows on Nightscout exactly as now, but Trio's stored mg/dL can differ by 1.
    static func storedEntries(fromNightscout entries: [(seconds: Int, value: Double)], kind: TherapyKind, nsMgdl: Bool) -> [TherapyEntry]? {
        let sorted = entries.sorted { $0.seconds < $1.seconds }
        guard let first = sorted.first, first.seconds == 0,
              sorted.allSatisfy({ $0.seconds % 1800 == 0 && $0.seconds < 24 * 3600 })
        else { return nil }
        var result: [TherapyEntry] = []
        for entry in nightscoutValues(sorted, kind: kind, nsMgdl: nsMgdl) {
            var value = entry.value
            if kind == .isf, !nsMgdl {
                guard let m = mgdl(fromMmolTenths: value) else { return nil }
                value = m
            }
            guard range(kind).contains(value) else { return nil }
            result.append(TherapyEntry(minutes: entry.minutes, value: value))
        }
        return merged(result)
    }

    /// True when every Nightscout value is exact in the unit it is read in: CR a whole tenth of g/U, ISF a whole mg/dL
    /// (mg/dL profile) or a whole tenth of mmol/L. Otherwise the saved copy is rounded (reconstructed).
    static func nightscoutIsExact(_ entries: [(seconds: Int, value: Double)], kind: TherapyKind, nsMgdl: Bool) -> Bool {
        let scale = kind == .isf && nsMgdl ? 1 : 10
        return entries.allSatisfy { entry in
            guard var scaled = Decimal(string: "\(entry.value)", locale: Locale(identifier: "en_US_POSIX")).map({ $0 * Decimal(scale) })
            else { return false }
            var rounded = Decimal()
            NSDecimalRound(&rounded, &scaled, 0, .plain)
            return rounded == scaled
        }
    }

    // MARK: Entries

    /// Sorted by start, adjacent equal values merged. Delivers the same 48 slots, so the hash does not change.
    static func merged(_ entries: [TherapyEntry]) -> [TherapyEntry] {
        var result: [TherapyEntry] = []
        for entry in entries.sorted(by: { $0.minutes < $1.minutes }) where entry.value != result.last?.value {
            result.append(entry)
        }
        return result
    }

    /// Adjacent equal slots merged: (start minute, value).
    static func slotSegments(_ slots: [Int]) -> [TherapyEntry] {
        var result: [TherapyEntry] = []
        for (i, value) in slots.enumerated() where result.last?.value != value {
            result.append(TherapyEntry(minutes: i * 30, value: value))
        }
        return result
    }

    static func range(_ kind: TherapyKind) -> ClosedRange<Int> {
        kind == .carbRatio ? crTenthsRange : isfMgdlRange
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func carbRatioSchedule(_ entries: [TherapyEntry]) -> [CarbRatioScheduleEntry] {
        merged(entries).map { CarbRatioScheduleEntry(start: clock($0.minutes), ratio: Decimal($0.value) / 10) }
    }

    static func isfSchedule(_ entries: [TherapyEntry]) -> [ISFScheduleEntry] {
        merged(entries).map { ISFScheduleEntry(start: clock($0.minutes), sensitivity: $0.value) }
    }

    // MARK: Display

    /// Text of tenths ("8.5", "-1.5").
    static func tenthsText(_ tenths: Int) -> String {
        (tenths < 0 ? "-" : "") + "\(abs(tenths) / 10).\(abs(tenths) % 10)"
    }

    /// A stored value in the unit shown: CR g/U; ISF mg/dL, or mmol/L when `mmol`.
    static func displayValue(_ stored: Int, kind: TherapyKind, mmol: Bool) -> Int {
        kind == .isf && mmol ? mmolTenths(mgdl: stored) : stored
    }

    /// A Nightscout-form slot value in the unit shown (for "dabar"). ISF uploaded in the other unit is converted.
    static func displayValue(nightscout value: Int, kind: TherapyKind, nsMgdl: Bool, mmol: Bool) -> Int {
        guard kind == .isf else { return value }
        switch (nsMgdl, mmol) {
        case (true, true): return mmolTenths(mgdl: value)
        case (false, false): return mgdl(fromMmolTenths: value) ?? Int((Double(value) / 0.555).rounded())
        default: return value
        }
    }

    /// Text of a value already in the shown unit.
    static func displayText(_ value: Int, kind: TherapyKind, mmol: Bool) -> String {
        kind == .isf && !mmol ? "\(value)" : tenthsText(value)
    }

    static func unit(_ kind: TherapyKind, mmol: Bool) -> String {
        kind == .carbRatio ? "g/U" : (mmol ? "mmol/L" : "mg/dL")
    }

    /// The stored value as shown; ISF in mmol/L also with its mg/dL ("8.3 mmol/L (150 mg/dL)").
    static func fullText(_ stored: Int, kind: TherapyKind, mmol: Bool) -> String {
        let shown = "\(displayText(displayValue(stored, kind: kind, mmol: mmol), kind: kind, mmol: mmol)) \(unit(kind, mmol: mmol))"
        return kind == .isf && mmol ? "\(shown) (\(stored) mg/dL)" : shown
    }

    // MARK: Comparison (activation)

    /// Lower CR or lower ISF gives MORE insulin (for the same carbs / the same glucose above target).
    enum InsulinDirection: Equatable {
        case more, less, same

        var text: String {
            switch self {
            case .more: return "daugiau insulino"
            case .less: return "mažiau insulino"
            case .same: return "be pokyčio"
            }
        }
    }

    static func direction(now: Int, new: Int) -> InsulinDirection {
        new < now ? .more : (new > now ? .less : .same)
    }

    /// Relative change in percent, rounded; nil when `now` is 0.
    static func percentChange(now: Int, new: Int) -> Int? {
        guard now != 0 else { return nil }
        return Int((Double(new - now) / Double(now) * 100).rounded())
    }

    struct ComparisonRow: Equatable {
        let minutes: Int
        let now: Int?
        let new: Int
    }

    /// Rows where the (now, new) pair changes, from 48 slots each (same unit).
    static func comparisonRows(now: [Int]?, new: [Int]) -> [ComparisonRow] {
        guard new.count == slotCount else { return [] }
        let current = now?.count == slotCount ? now : nil
        var rows: [ComparisonRow] = []
        for slot in 0 ..< slotCount {
            let row = ComparisonRow(minutes: slot * 30, now: current?[slot], new: new[slot])
            if let last = rows.last, last.now == row.now, last.new == row.new { continue }
            rows.append(row)
        }
        return rows
    }

    /// More than `threshold` percent, decided in integers (no rounding): |new − now| × 100 > threshold × now.
    static func exceeds(now: Int, new: Int, threshold: Int = 20) -> Bool {
        now > 0 && abs(new - now) * 100 > threshold * now
    }

    /// The largest change above `threshold` percent (rows in Nightscout form), or nil.
    static func largestChange(_ rows: [ComparisonRow], above threshold: Int = 20) -> ComparisonRow? {
        rows.filter { row in row.now.map { exceeds(now: $0, new: row.new, threshold: threshold) } ?? false }
            .max { a, b in
                // |Δa|/a.now < |Δb|/b.now, cross-multiplied (integers, no rounding)
                abs(a.new - a.now!) * b.now! < abs(b.new - b.now!) * a.now!
            }
    }

    /// Percent with one decimal for the warning ("-20.4"); display only.
    static func percentText(now: Int, new: Int) -> String {
        guard now != 0 else { return "" }
        return String(format: "%+.1f", Double(new - now) / Double(now) * 100)
    }

    // MARK: Editor input

    /// Typed value → stored unit (CR tenths, ISF mg/dL), or the error text.
    static func parse(_ text: String, kind: TherapyKind, mmol: Bool) -> Result<Int, ParseError> {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        // Decimal(string:) accepts a numeric prefix ("1.2x" → 1.2), so the text itself is checked first.
        guard !trimmed.isEmpty, trimmed.allSatisfy({ "0123456789.".contains($0) }), trimmed.filter({ $0 == "." }).count <= 1,
              let number = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
        else {
            return .failure(ParseError("neteisinga reikšmė."))
        }
        if kind == .isf, !mmol {
            guard let tenths = exactScaled(number, by: 1) else { return .failure(ParseError("tik sveiki mg/dL.")) }
            return .success(tenths)
        }
        guard let tenths = exactScaled(number, by: 10) else { return .failure(ParseError("tik 0.1 tikslumu.")) }
        if kind == .carbRatio { return .success(tenths) }
        guard let mgdl = mgdl(fromMmolTenths: tenths) else { return .failure(ParseError("turi būti 0.5–30.0 mmol/L.")) }
        return .success(mgdl)
    }

    struct ParseError: Error, Equatable {
        let text: String
        init(_ text: String) { self.text = text }
    }

    private static func exactScaled(_ value: Decimal, by scale: Int) -> Int? {
        var scaled = value * Decimal(scale)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard rounded == scaled else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// Text the editor starts with for a stored value.
    static func editText(_ stored: Int, kind: TherapyKind, mmol: Bool) -> String {
        displayText(displayValue(stored, kind: kind, mmol: mmol), kind: kind, mmol: mmol)
    }

    // MARK: Validation (the same rules Trio applies; Trio stays the authority)

    enum Problem: Equatable {
        case name(String)
        case schedule(String)
        case entry(Int, String)

        var text: String {
            switch self {
            case let .name(text), let .schedule(text): return text
            case let .entry(minutes, text): return "\(TherapyProfileMath.clock(minutes)) — " + text
            }
        }
    }

    static func validate(name: String, kind: TherapyKind, entries: [TherapyEntry]) -> [Problem] {
        var problems: [Problem] = []
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.count > maxNameLength {
            problems.append(.name("Pavadinimas turi būti 1–\(maxNameLength) simbolių."))
        } else if trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0 == "\"" }) {
            problems.append(.name("Pavadinime negali būti kabučių ar valdymo simbolių."))
        }
        guard (1 ... maxEntries).contains(entries.count) else {
            return problems + [.schedule("Turi būti 1–\(maxEntries) įrašai.")]
        }
        if entries[0].minutes != 0 { problems.append(.schedule("Pirmas įrašas turi prasidėti 00:00.")) }
        for (i, entry) in entries.enumerated() {
            if entry.minutes % 30 != 0 || entry.minutes < 0 || entry.minutes >= 24 * 60 {
                problems.append(.entry(entry.minutes, "laikas turi būti HH:00 arba HH:30."))
            } else if i > 0, entry.minutes <= entries[i - 1].minutes {
                problems.append(.entry(entry.minutes, "laikai turi didėti (pasikartoja arba ne iš eilės)."))
            }
            if !range(kind).contains(entry.value) {
                problems.append(.entry(entry.minutes, kind == .carbRatio
                        ? "turi būti 1.0–50.0 g/U."
                        : "turi būti 9–540 mg/dL (0.5–30.0 mmol/L)."))
            }
        }
        return problems
    }
}
