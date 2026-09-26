// LoopFollow
// TrioDosingMode.swift

import Foundation

/// Trio's dosing mode as uploaded in devicestatus `openaps.dosingMode` (Trio v1.0.1+) and as sent in the
/// `set_dosing_mode` remote command. Raw values must match Trio's `DosingMode` rawValue exactly.
enum TrioDosingMode: String, CaseIterable, Identifiable {
    case closed
    case open
    case lowGlucoseSuspend
    case basalTesting

    var id: String { rawValue }

    /// Trio's own names for the modes (Trio `DosingMode.displayName`).
    var displayName: String {
        switch self {
        case .closed: return "Closed Loop"
        case .open: return "Open Loop"
        case .lowGlucoseSuspend: return "Low Glucose Suspend"
        case .basalTesting: return "Basal Testing"
        }
    }

    /// Short form for the Info table.
    var shortName: String {
        switch self {
        case .closed: return "Closed Loop"
        case .open: return "Open Loop"
        case .lowGlucoseSuspend: return "LGS"
        case .basalTesting: return "Basal Test"
        }
    }

    /// `openaps.dosingMode` from a devicestatus `openaps` record; nil when the field is missing
    /// (older Trio, other uploaders) or not one of the four known values.
    static func from(openaps: [String: AnyObject]?) -> TrioDosingMode? {
        guard let raw = openaps?["dosingMode"] as? String else { return nil }
        return TrioDosingMode(rawValue: raw)
    }

    // MARK: - Remembered reading

    /// A mode is shown as current for this long after the devicestatus that carried it; after that it is Unknown.
    static let staleAfter: TimeInterval = 15 * 60

    /// The newest mode seen and when the devicestatus that carried it was written.
    struct Reading: Equatable {
        let raw: String
        let at: TimeInterval?
    }

    /// The reading after a devicestatus arrives. Only a record that carries a non-empty `openaps.dosingMode`
    /// (a Trio record) replaces it; any other record returns `current` unchanged, so a second uploader on the
    /// same Nightscout site neither clears the mode nor makes it flicker.
    static func merge(_ current: Reading?, deviceStatus: [String: AnyObject]?) -> Reading? {
        let openaps = deviceStatus?["openaps"] as? [String: AnyObject]
        guard let raw = openaps?["dosingMode"] as? String, !raw.isEmpty else { return current }
        return Reading(raw: raw, at: timestamp(ofDeviceStatus: deviceStatus))
    }

    /// A devicestatus time up to this far ahead of the phone's clock is ordinary skew and still counts as fresh;
    /// further ahead, the time cannot be trusted and the mode is Unknown.
    static let futureTolerance: TimeInterval = 2 * 60

    /// What the remembered reading means right now.
    enum Status: Equatable {
        /// No devicestatus with a mode has been seen.
        case none
        /// Fresh and one of the four modes.
        case current(TrioDosingMode)
        /// Fresh, but a mode this build does not know (e.g. a newer Trio).
        case unrecognized(String)
        /// Older than `staleAfter`; `ageMinutes` is nil when the record had no time.
        case stale(ageMinutes: Int?)
        /// Time more than `futureTolerance` ahead of now, so its age is unknowable.
        case future
    }

    static func status(_ reading: Reading?, now: TimeInterval) -> Status {
        guard let reading else { return .none }
        guard let at = reading.at else { return .stale(ageMinutes: nil) }
        if at - now > futureTolerance { return .future }
        if now - at > staleAfter { return .stale(ageMinutes: Int((now - at) / 60)) }
        if let mode = TrioDosingMode(rawValue: reading.raw) { return .current(mode) }
        return .unrecognized(reading.raw)
    }

    /// Whole minutes since the reading's devicestatus. nil when there is no reading, it is undated, or its time is
    /// ahead of now — a negative age is never reported as 0.
    static func ageMinutes(_ reading: Reading?, now: TimeInterval) -> Int? {
        guard let at = reading?.at, at <= now else { return nil }
        return Int((now - at) / 60)
    }

    /// True when there is a reading but its age cannot be trusted as current: older than `staleAfter`, undated,
    /// or from the future beyond `futureTolerance`.
    static func isStale(_ reading: Reading?, now: TimeInterval) -> Bool {
        switch status(reading, now: now) {
        case .stale, .future: return true
        case .none, .current, .unrecognized: return false
        }
    }

    /// The mode to treat as current; nil unless the reading is fresh and one of the four.
    static func current(_ reading: Reading?, now: TimeInterval) -> TrioDosingMode? {
        if case let .current(mode) = status(reading, now: now) { return mode }
        return nil
    }

    /// Info table text.
    static func infoText(_ reading: Reading?, now: TimeInterval) -> String {
        switch status(reading, now: now) {
        case .none: return "—"
        case let .current(mode): return mode.shortName
        case let .unrecognized(raw): return raw
        case let .stale(age?): return "Unknown (\(age) min)"
        case .stale(nil): return "Unknown"
        case .future: return "Unknown (laikas ateityje)"
        }
    }

    /// Extra line for the send confirmation when the current mode is not a fresh, known one; nil when it is.
    static func confirmationNote(_ reading: Reading?, now: TimeInterval) -> String? {
        switch status(reading, now: now) {
        case .current: return nil
        case let .unrecognized(raw): return "Dabartinis režimas neatpažintas (\(raw))"
        case let .stale(age?): return "Dabartinis režimas nežinomas (paskutiniai duomenys prieš \(age) min)"
        case .stale(nil): return "Dabartinis režimas nežinomas (paskutinių duomenų laikas nežinomas)"
        case .future: return "Dabartinis režimas nežinomas (laikas ateityje)"
        case .none: return "Dabartinis režimas nežinomas (duomenų nėra)"
        }
    }

    /// When a devicestatus document was written: `mills` when present, else `created_at`.
    static func timestamp(ofDeviceStatus status: [String: AnyObject]?) -> TimeInterval? {
        if let mills = status?["mills"] as? Double { return mills / 1000 }
        guard let createdAt = status?["created_at"] as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: createdAt) { return date.timeIntervalSince1970 }
        return ISO8601DateFormatter().date(from: createdAt)?.timeIntervalSince1970
    }
}
