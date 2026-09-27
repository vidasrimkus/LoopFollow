// LoopFollow
// PushMessage.swift

import Foundation

struct EncryptedPushMessage: Encodable {
    let aps: APSPayload
    let encryptedData: String

    init(encryptedData: String, commandType: TRCCommandType, dosingMode: String? = nil) {
        self.encryptedData = encryptedData
        aps = APSPayload(alert: Self.alertText(commandType: commandType, dosingMode: dosingMode))
    }

    /// Visible alert on the Trio phone. set_dosing_mode names the target mode so it is clear what the
    /// phone is being switched to; every other command keeps its existing text.
    static func alertText(commandType: TRCCommandType, dosingMode: String?) -> String {
        if commandType == .setDosingMode, let raw = dosingMode {
            let name = TrioDosingMode(rawValue: raw)?.displayName ?? raw
            return "Remote Command: \(commandType.displayName) → \(name)"
        }
        return "Remote Command: \(commandType.displayName)"
    }

    struct APSPayload: Encodable {
        let contentAvailable: Int = 1
        let interruptionLevel: String = "time-sensitive"
        let alert: String

        enum CodingKeys: String, CodingKey {
            case contentAvailable = "content-available"
            case interruptionLevel = "interruption-level"
            case alert
        }
    }

    enum CodingKeys: String, CodingKey {
        case aps
        case encryptedData = "encrypted_data"
    }
}

struct CommandPayload: Encodable {
    var user: String
    var commandType: TRCCommandType
    var timestamp: TimeInterval

    var bolusAmount: Decimal?
    var target: Int?
    var duration: Int?
    var carbs: Int?
    var protein: Int?
    var fat: Int?
    var overrideName: String?
    var scheduledTime: TimeInterval?
    /// set_dosing_mode only: a Trio DosingMode rawValue ("closed", "open", "lowGlucoseSuspend", "basalTesting").
    /// nil is not encoded, so no other command carries the key.
    var dosingMode: String?
    /// set_basal_schedule only (Trio CUSTOMIZATIONS.md §7): the schedule, its name, and the hash of Trio's active
    /// schedule as this phone saw it in Nightscout. nil is not encoded.
    var basalSchedule: [BasalScheduleSegment]?
    var basalScheduleName: String?
    var expectedActiveHash: String?
    var returnNotification: ReturnNotificationInfo?

    struct ReturnNotificationInfo: Encodable {
        let productionEnvironment: Bool
        let deviceToken: String
        let bundleId: String
        let teamId: String
        let keyId: String
        let apnsKey: String

        enum CodingKeys: String, CodingKey {
            case productionEnvironment = "production_environment"
            case deviceToken = "device_token"
            case bundleId = "bundle_id"
            case teamId = "team_id"
            case keyId = "key_id"
            case apnsKey = "apns_key"
        }
    }

    enum CodingKeys: String, CodingKey {
        case user
        case commandType = "command_type"
        case timestamp
        case bolusAmount = "bolus_amount"
        case target
        case duration
        case carbs
        case protein
        case fat
        case overrideName
        case scheduledTime = "scheduled_time"
        case dosingMode = "dosing_mode"
        case basalSchedule = "basal_schedule"
        case basalScheduleName = "basal_schedule_name"
        case expectedActiveHash = "expected_active_hash"
        case returnNotification = "return_notification"
    }
}
