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

    private let now: TimeInterval = 1_790_424_000

    private func trioStatus(_ raw: String, at: TimeInterval) -> [String: AnyObject] {
        let openaps: [String: AnyObject] = ["dosingMode": raw as AnyObject, "iob": ["iob": 0.5] as AnyObject]
        return ["mills": at * 1000 as AnyObject, "openaps": openaps as AnyObject]
    }

    @Test("devicestatus openaps.dosingMode parses", arguments: TrioDosingMode.allCases)
    func parsesEachMode(mode: TrioDosingMode) {
        let openaps: [String: AnyObject] = ["dosingMode": mode.rawValue as AnyObject]
        #expect(TrioDosingMode.from(openaps: openaps) == mode)
        let reading = TrioDosingMode.merge(nil, deviceStatus: trioStatus(mode.rawValue, at: now - 60))
        #expect(reading == TrioDosingMode.Reading(raw: mode.rawValue, at: now - 60))
        #expect(TrioDosingMode.current(reading, now: now) == mode)
        #expect(TrioDosingMode.infoText(reading, now: now) == mode.shortName)
    }

    @Test("No reading shows a dash")
    func noReading() {
        let openaps: [String: AnyObject] = ["iob": ["iob": 0.5] as AnyObject]
        #expect(TrioDosingMode.from(openaps: openaps) == nil)
        #expect(TrioDosingMode.merge(nil, deviceStatus: ["openaps": openaps as AnyObject]) == nil)
        #expect(TrioDosingMode.infoText(nil, now: now) == "—")
        #expect(TrioDosingMode.current(nil, now: now) == nil)
    }

    @Test("A record without openaps.dosingMode neither changes nor clears the mode")
    func recordWithoutModeKeepsReading() {
        let kept = TrioDosingMode.Reading(raw: "basalTesting", at: now - 120)
        let loopRecord: [String: AnyObject] = ["mills": now * 1000 as AnyObject, "loop": ["iob": ["iob": 1.0]] as AnyObject]
        let openapsWithoutMode: [String: AnyObject] = ["mills": now * 1000 as AnyObject, "openaps": ["iob": ["iob": 1.0]] as AnyObject]
        let blankMode: [String: AnyObject] = ["mills": now * 1000 as AnyObject, "openaps": ["dosingMode": ""] as AnyObject]
        for status in [loopRecord, openapsWithoutMode, blankMode, [:]] {
            #expect(TrioDosingMode.merge(kept, deviceStatus: status) == kept)
        }
        #expect(TrioDosingMode.merge(kept, deviceStatus: nil) == kept)
        // A Trio record does replace it.
        #expect(TrioDosingMode.merge(kept, deviceStatus: trioStatus("closed", at: now)) == TrioDosingMode.Reading(raw: "closed", at: now))
    }

    @Test("Older than 15 min is Unknown, with its age")
    func staleIsUnknown() {
        let fresh = TrioDosingMode.Reading(raw: "open", at: now - 15 * 60)
        #expect(TrioDosingMode.current(fresh, now: now) == .open)
        #expect(TrioDosingMode.infoText(fresh, now: now) == "Open Loop")

        let stale = TrioDosingMode.Reading(raw: "open", at: now - 15 * 60 - 1)
        #expect(TrioDosingMode.isStale(stale, now: now))
        #expect(TrioDosingMode.current(stale, now: now) == nil)
        #expect(TrioDosingMode.infoText(stale, now: now) == "Unknown (15 min)")
        #expect(TrioDosingMode.infoText(TrioDosingMode.Reading(raw: "closed", at: now - 47 * 60), now: now) == "Unknown (47 min)")

        let undated = TrioDosingMode.Reading(raw: "closed", at: nil)
        #expect(TrioDosingMode.current(undated, now: now) == nil)
        #expect(TrioDosingMode.infoText(undated, now: now) == "Unknown")
    }

    @Test("A time up to 2 min in the future is fresh; beyond that the mode is Unknown")
    func futureTimestamps() {
        let slightlyAhead = TrioDosingMode.Reading(raw: "basalTesting", at: now + 60)
        #expect(TrioDosingMode.status(slightlyAhead, now: now) == .current(.basalTesting))
        #expect(TrioDosingMode.current(slightlyAhead, now: now) == .basalTesting)
        #expect(TrioDosingMode.infoText(slightlyAhead, now: now) == "Basal Test")
        #expect(TrioDosingMode.ageMinutes(slightlyAhead, now: now) == nil) // never "0 min" for a negative age

        let farAhead = TrioDosingMode.Reading(raw: "basalTesting", at: now + 3 * 60)
        #expect(TrioDosingMode.status(farAhead, now: now) == .future)
        #expect(TrioDosingMode.current(farAhead, now: now) == nil)
        #expect(TrioDosingMode.isStale(farAhead, now: now))
        #expect(TrioDosingMode.infoText(farAhead, now: now) == "Unknown (laikas ateityje)")
        #expect(TrioDosingMode.ageMinutes(farAhead, now: now) == nil)
        #expect(TrioDosingMode.confirmationNote(farAhead, now: now) == "Dabartinis režimas nežinomas (laikas ateityje)")
    }

    @Test("Confirmation note: none for a fresh known mode; unrecognized names the value; stale gives the age")
    func confirmationNotes() {
        #expect(TrioDosingMode.confirmationNote(TrioDosingMode.Reading(raw: "open", at: now - 60), now: now) == nil)
        #expect(TrioDosingMode.confirmationNote(TrioDosingMode.Reading(raw: "autoPilot", at: now - 60), now: now)
            == "Dabartinis režimas neatpažintas (autoPilot)")
        #expect(TrioDosingMode.confirmationNote(TrioDosingMode.Reading(raw: "open", at: now - 20 * 60), now: now)
            == "Dabartinis režimas nežinomas (paskutiniai duomenys prieš 20 min)")
        #expect(TrioDosingMode.confirmationNote(TrioDosingMode.Reading(raw: "open", at: nil), now: now)
            == "Dabartinis režimas nežinomas (paskutinių duomenų laikas nežinomas)")
        #expect(TrioDosingMode.confirmationNote(nil, now: now) == "Dabartinis režimas nežinomas (duomenų nėra)")
    }

    @Test("The current mode's row stays enabled and its confirmation asks to send anyway", arguments: TrioDosingMode.allCases)
    func currentModeRowEnabled(mode: TrioDosingMode) {
        let reading = TrioDosingMode.Reading(raw: mode.rawValue, at: now - 4 * 60)
        #expect(TrioDosingMode.current(reading, now: now) == mode) // shown with ✓
        #expect(TrioDosingMode.isRowEnabled(isLoading: false))
        #expect(!TrioDosingMode.isRowEnabled(isLoading: true))
        #expect(TrioDosingMode.sameModeNote(selected: mode, reading: reading, now: now)
            == "Pagal duomenis (prieš 4 min) Trio jau šiame režime. Siųsti vis tiek?")
        for other in TrioDosingMode.allCases where other != mode {
            #expect(TrioDosingMode.sameModeNote(selected: other, reading: reading, now: now) == nil)
        }
    }

    @Test("No same-mode line when the data is stale, missing or slightly ahead says 'ką tik'")
    func sameModeNoteEdges() {
        let stale = TrioDosingMode.Reading(raw: "open", at: now - 20 * 60)
        #expect(TrioDosingMode.sameModeNote(selected: .open, reading: stale, now: now) == nil)
        #expect(TrioDosingMode.sameModeNote(selected: .open, reading: nil, now: now) == nil)
        let slightlyAhead = TrioDosingMode.Reading(raw: "open", at: now + 60)
        #expect(TrioDosingMode.sameModeNote(selected: .open, reading: slightlyAhead, now: now)
            == "Pagal duomenis (ką tik) Trio jau šiame režime. Siųsti vis tiek?")
    }

    @Test("Unknown dosingMode is not treated as a known mode")
    func unknownValue() {
        let openaps: [String: AnyObject] = ["dosingMode": "teleportation" as AnyObject]
        #expect(TrioDosingMode.from(openaps: openaps) == nil)
        let reading = TrioDosingMode.merge(nil, deviceStatus: trioStatus("teleportation", at: now))
        #expect(TrioDosingMode.current(reading, now: now) == nil)
        #expect(TrioDosingMode.infoText(reading, now: now) == "teleportation")
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
