// LoopFollow
// TRCCommandType.swift

import Foundation

enum TRCCommandType: String, Encodable {
    case bolus
    case tempTarget = "temp_target"
    case cancelTempTarget = "cancel_temp_target"
    case meal
    case startOverride = "start_override"
    case cancelOverride = "cancel_override"
    case setDosingMode = "set_dosing_mode"
    case setBasalSchedule = "set_basal_schedule"

    var displayName: String {
        switch self {
        case .bolus: return "Bolus"
        case .tempTarget: return "Temp Target"
        case .cancelTempTarget: return "Cancel Temp Target"
        case .meal: return "Meal"
        case .startOverride: return "Start Override"
        case .cancelOverride: return "Cancel Override"
        case .setDosingMode: return "Dosing Mode"
        case .setBasalSchedule: return "Basal Schedule"
        }
    }
}
