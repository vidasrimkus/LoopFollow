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

    /// Whole minutes since the reading's devicestatus; nil when there is no reading or its time is unknown.
    static func ageMinutes(_ reading: Reading?, now: TimeInterval) -> Int? {
        guard let at = reading?.at else { return nil }
        return max(0, Int((now - at) / 60))
    }

    /// True when there is a reading but it cannot be trusted as current: older than `staleAfter`, or undated.
    static func isStale(_ reading: Reading?, now: TimeInterval) -> Bool {
        guard let reading else { return false }
        guard let at = reading.at else { return true }
        return now - at > staleAfter
    }

    /// The mode to treat as current; nil when there is no reading, it is stale, or it is not one of the four.
    static func current(_ reading: Reading?, now: TimeInterval) -> TrioDosingMode? {
        guard let reading, !isStale(reading, now: now) else { return nil }
        return TrioDosingMode(rawValue: reading.raw)
    }

    /// Info table text: "—" with no reading, "Unknown (N min)" when stale, else the short name
    /// (the raw value for a mode this build does not know).
    static func infoText(_ reading: Reading?, now: TimeInterval) -> String {
        guard let reading else { return "—" }
        if isStale(reading, now: now) {
            if let age = ageMinutes(reading, now: now) { return "Unknown (\(age) min)" }
            return "Unknown"
        }
        return TrioDosingMode(rawValue: reading.raw)?.shortName ?? reading.raw
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
