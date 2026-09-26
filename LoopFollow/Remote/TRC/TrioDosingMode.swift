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

    /// Info table text: short name, the raw value for an unknown mode, "—" when there is none.
    static func infoText(openaps: [String: AnyObject]?) -> String {
        if let mode = from(openaps: openaps) { return mode.shortName }
        if let raw = openaps?["dosingMode"] as? String, !raw.isEmpty { return raw }
        return "—"
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
