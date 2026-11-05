// LoopFollow
// TherapyCommandStatusTests.swift

import Foundation
import Testing

@testable import LoopFollow

@Suite("Correlated Trio therapy results")
struct TherapyCommandStatusTests {
    private func response(_ id: UUID, command: String = "set_carb_ratios", success: Bool = true, message: String = "done") -> [AnyHashable: Any] {
        ["command_id": id.uuidString, "command_type": command, "command_status": success ? "success" : "failed", "aps": ["alert": ["body": message]]]
    }

    @Test("HTTP 200 means sent only; a matching Trio response means applied") func sentVersusApplied() throws {
        let name = "TherapyCommandStatusTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let tracker = TherapyCommandStatus(defaults: defaults)
        let id = tracker.begin(kind: .carbRatio, command: .setCarbRatios)
        tracker.sent(kind: .carbRatio, id: id, success: true, error: nil)
        #expect(tracker.record(.carbRatio)?.phase == .sent)
        #expect(tracker.record(.carbRatio)?.text(now: Date()).hasPrefix("Išsiųsta") == true)
        #expect(tracker.receive(response(id)) == .carbRatio)
        #expect(tracker.record(.carbRatio)?.phase == .applied)
        #expect(tracker.record(.carbRatio)?.text(now: Date()).hasPrefix("Trio pritaikė") == true)
        tracker.sent(kind: .carbRatio, id: id, success: false, error: "late HTTP error")
        #expect(tracker.record(.carbRatio)?.phase == .applied)
    }

    @Test("No Trio reply after five minutes is unknown; pending state survives relaunch") func timeoutAndRelaunch() throws {
        let name = "TherapyCommandStatusTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let start = Date(timeIntervalSince1970: 1000)
        let tracker = TherapyCommandStatus(defaults: defaults)
        let id = tracker.begin(kind: .isf, command: .setISF, now: start)
        tracker.sent(kind: .isf, id: id, success: true, error: nil)
        let relaunched = TherapyCommandStatus(defaults: defaults)
        let record = try #require(relaunched.record(.isf))
        #expect(record.id == id)
        #expect(record.isPending(now: start.addingTimeInterval(299)))
        #expect(!record.isPending(now: start.addingTimeInterval(300)))
        #expect(record.text(now: start.addingTimeInterval(300)).hasPrefix("Trio neatsakė"))
        #expect(!record.text(now: start.addingTimeInterval(300)).contains("Trio pritaikė"))
        #expect(relaunched.receive(response(id, command: "set_isf")) == .isf) // late truth is still shown
    }

    @Test("Stale/unrelated/duplicate replies cannot confirm a newer or different command") func correlation() throws {
        let name = "TherapyCommandStatusTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let tracker = TherapyCommandStatus(defaults: defaults)
        let old = tracker.begin(kind: .carbRatio, command: .setCarbRatios)
        let latest = tracker.begin(kind: .carbRatio, command: .restorePreviousCarbRatios)
        let isf = tracker.begin(kind: .isf, command: .setISF)
        #expect(tracker.receive(response(old)) == nil)
        #expect(tracker.receive(response(latest, command: "set_carb_ratios")) == nil)
        #expect(tracker.record(.carbRatio)?.phase == .sending)
        #expect(tracker.receive(response(isf, command: "set_isf")) == .isf)
        #expect(tracker.receive(response(latest, command: "restore_previous_carb_ratios")) == .carbRatio)
        #expect(tracker.receive(response(latest, command: "restore_previous_carb_ratios", success: false)) == nil)
        #expect(tracker.record(.carbRatio)?.phase == .applied)
        #expect(tracker.receive(["command_type": "set_isf", "command_status": "success"]) == nil)
    }

    @Test("Trio rejection reason, including exact percentage, is visible; early reply wins over HTTP") func rejectedReason() throws {
        let name = "TherapyCommandStatusTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let tracker = TherapyCommandStatus(defaults: defaults)
        let id = tracker.begin(kind: .carbRatio, command: .setCarbRatios)
        let message = "CR 10:00: 10 → 12.1 g/U (21%). Maksimalus pokytis vienu kartu yra ±20 %."
        #expect(tracker.receive(response(id, success: false, message: message)) == .carbRatio)
        tracker.sent(kind: .carbRatio, id: id, success: true, error: nil)
        #expect(tracker.record(.carbRatio)?.phase == .rejected)
        #expect(tracker.record(.carbRatio)?.text(now: Date()) == "Trio atmetė: " + message)
    }

    @Test("Restore payload contains correlation and expected hash, never a client-supplied schedule") func restoreEncoding() throws {
        let manager = PushNotificationManager()
        for kind in TherapyKind.allCases {
            let id = UUID()
            let payload = manager.restoreTherapyPayload(kind: kind, expectedActiveHash: "abc", commandID: id)
            let data = try JSONEncoder().encode(payload)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["command_id"] as? String == id.uuidString)
            #expect(json["expected_active_hash"] as? String == "abc")
            #expect(json["command_type"] as? String == (kind == .carbRatio ? "restore_previous_carb_ratios" : "restore_previous_isf"))
            #expect(json["carb_ratio_schedule"] == nil && json["isf_schedule"] == nil)
        }
    }
}
