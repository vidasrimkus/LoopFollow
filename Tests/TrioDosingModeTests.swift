// LoopFollow
// TrioDosingModeTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct TrioDosingModeTests {
    private func encodedJSON(_ payload: CommandPayload) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Raw values are exactly Trio's DosingMode raw values")
    func rawValuesMatchTrio() {
        #expect(TrioDosingMode.allCases.map(\.rawValue) == ["closed", "open", "lowGlucoseSuspend", "basalTesting"])
        #expect(TRCCommandType.setDosingMode.rawValue == "set_dosing_mode")
        #expect(TRCCommandType.setDosingMode.displayName == "Dosing Mode")
    }

    @Test("set_dosing_mode encodes command_type and dosing_mode", arguments: TrioDosingMode.allCases)
    func encodesDosingMode(mode: TrioDosingMode) throws {
        let payload = CommandPayload(user: "LoopFollow", commandType: .setDosingMode, timestamp: 1_790_400_000, dosingMode: mode.rawValue)
        let json = try encodedJSON(payload)
        #expect(json["command_type"] as? String == "set_dosing_mode")
        #expect(json["dosing_mode"] as? String == mode.rawValue)
        #expect(json["user"] as? String == "LoopFollow")
        #expect(json["timestamp"] as? Double == 1_790_400_000)
    }

    @Test("Other commands do not carry dosing_mode")
    func otherCommandsOmitDosingMode() throws {
        let override = CommandPayload(user: "u", commandType: .startOverride, timestamp: 1, overrideName: "Exercise")
        let cancelTT = CommandPayload(user: "u", commandType: .cancelTempTarget, timestamp: 1)
        let meal = CommandPayload(user: "u", commandType: .meal, timestamp: 1, carbs: 20, protein: 0, fat: 0)
        for payload in [override, cancelTT, meal] {
            let json = try encodedJSON(payload)
            #expect(json["dosing_mode"] == nil)
        }
        #expect(try encodedJSON(override)["overrideName"] as? String == "Exercise")
    }

    @Test("Alert text names the target mode; other commands keep theirs")
    func alertText() {
        #expect(EncryptedPushMessage.alertText(commandType: .setDosingMode, dosingMode: "basalTesting") == "Remote Command: Dosing Mode → Basal Testing")
        #expect(EncryptedPushMessage.alertText(commandType: .setDosingMode, dosingMode: "closed") == "Remote Command: Dosing Mode → Closed Loop")
        #expect(EncryptedPushMessage.alertText(commandType: .startOverride, dosingMode: nil) == "Remote Command: Start Override")
        #expect(EncryptedPushMessage.alertText(commandType: .bolus, dosingMode: "closed") == "Remote Command: Bolus")
    }

    @Test("devicestatus openaps.dosingMode parses", arguments: TrioDosingMode.allCases)
    func parsesEachMode(mode: TrioDosingMode) {
        let openaps: [String: AnyObject] = ["dosingMode": mode.rawValue as AnyObject]
        #expect(TrioDosingMode.from(openaps: openaps) == mode)
        #expect(TrioDosingMode.infoText(openaps: openaps) == mode.shortName)
    }

    @Test("devicestatus without dosingMode shows a dash")
    func missingField() {
        let openaps: [String: AnyObject] = ["iob": ["iob": 0.5] as AnyObject]
        #expect(TrioDosingMode.from(openaps: openaps) == nil)
        #expect(TrioDosingMode.infoText(openaps: openaps) == "—")
        #expect(TrioDosingMode.infoText(openaps: nil) == "—")
    }

    @Test("Unknown dosingMode is not treated as a known mode")
    func unknownValue() {
        let openaps: [String: AnyObject] = ["dosingMode": "teleportation" as AnyObject]
        #expect(TrioDosingMode.from(openaps: openaps) == nil)
        #expect(TrioDosingMode.infoText(openaps: openaps) == "teleportation")
    }

    @Test("devicestatus timestamp from mills or created_at")
    func timestamps() {
        #expect(TrioDosingMode.timestamp(ofDeviceStatus: ["mills": 1_790_400_000_000.0 as AnyObject]) == 1_790_400_000)
        #expect(TrioDosingMode.timestamp(ofDeviceStatus: ["created_at": "2026-09-26T12:00:00.000Z" as AnyObject]) == 1_790_424_000)
        #expect(TrioDosingMode.timestamp(ofDeviceStatus: ["created_at": "2026-09-26T12:00:00Z" as AnyObject]) == 1_790_424_000)
        #expect(TrioDosingMode.timestamp(ofDeviceStatus: nil) == nil)
    }

    @Test("Mode row is appended last so existing rows keep their storage index")
    func infoTypeAppendedLast() {
        #expect(InfoType.dosingMode.rawValue == InfoType.allCases.count - 1)
        #expect(InfoType.dbSize.rawValue == 20)
        #expect(InfoType.dosingMode.name == "Mode")
    }
}
