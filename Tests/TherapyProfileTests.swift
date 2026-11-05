// LoopFollow
// TherapyProfileTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct TherapyProfileTests {
    private func e(_ pairs: [(String, Int)]) -> [TherapyEntry] {
        pairs.map { TherapyEntry(minutes: Int($0.0.prefix(2))! * 60 + Int($0.0.suffix(2))!, value: $0.1) }
    }

    private func crSlots(_ pairs: [(String, Int)]) -> [Int] { TherapyProfileMath.slots(e(pairs)) }

    // Contract vectors (CR in tenths, ISF in mg/dL)
    private var cr1: [TherapyEntry] { e([("00:00", 100), ("06:00", 85), ("11:00", 120), ("17:00", 105)]) }
    private var cr3: [TherapyEntry] { e([("00:00", 90), ("07:30", 75), ("20:00", 110)]) }
    private var isf1: [TherapyEntry] { e([("00:00", 180), ("08:00", 150), ("22:00", 200)]) }
    private var isf2: [TherapyEntry] { e([("00:00", 46), ("12:30", 47)]) }

    // MARK: Hash vectors — must equal Trio

    @Test("CR hash vectors CR1–CR4 (contract)")
    func crVectors() {
        #expect(TherapyProfileMath.crHash(tenths: TherapyProfileMath.slots(cr1)) == "d0f731e0166dbc52")
        #expect(TherapyProfileMath.crHash(tenths: crSlots([("00:00", 100)])) == "eb0120f2d30d1482")
        #expect(TherapyProfileMath.crHash(tenths: TherapyProfileMath.slots(cr3)) == "82bc62b67556f34a")
        #expect(TherapyProfileMath.crHash(tenths: crSlots([("00:00", 90), ("03:00", 90), ("07:30", 75), ("20:00", 110)])) == "82bc62b67556f34a")
        #expect(TherapyProfileMath.crHash(tenths: crSlots([("06:00", 80), ("21:00", 120)])) == "ae96c8ecc9e86a8b")
        #expect(TherapyProfileMath.crHash(tenths: crSlots([("21:00", 120), ("06:00", 80)])) == "ae96c8ecc9e86a8b")
        #expect(!TherapyProfileMath.validate(name: "CR4", kind: .carbRatio, entries: e([("06:00", 80), ("21:00", 120)])).isEmpty)
        // The profile-side helper gives the same.
        #expect(TherapyProfileMath.nightscoutFormHash(cr1, kind: .carbRatio, nsMgdl: false) == "d0f731e0166dbc52")
        #expect(TherapyProfileMath.nightscoutFormHash(cr1, kind: .carbRatio, nsMgdl: true) == "d0f731e0166dbc52")
        // Canonical slot counts: 100×12, 85×10, 120×12, 105×14.
        #expect(TherapyProfileMath.slots(cr1) == Array(repeating: 100, count: 12) + Array(repeating: 85, count: 10)
            + Array(repeating: 120, count: 12) + Array(repeating: 105, count: 14))
    }

    @Test("CR hash from Nightscout carbratio entries (g/U doubles)")
    func crFromNightscout() {
        let ns: [(seconds: Int, value: Double)] = [(0, 10.0), (21600, 8.5), (39600, 12.0), (61200, 10.5)]
        #expect(TherapyProfileMath.nightscoutHash(ns, kind: .carbRatio, nsMgdl: false) == "d0f731e0166dbc52")
        #expect(TherapyProfileMath.nightscoutHash(ns, kind: .carbRatio, nsMgdl: true) == "d0f731e0166dbc52")
        #expect(TherapyProfileMath.nightscoutHash([(0, 10)], kind: .carbRatio, nsMgdl: false) == "eb0120f2d30d1482")
        #expect(TherapyProfileMath.nightscoutHash([(72000, 11.0), (0, 9.0), (27000, 7.5)], kind: .carbRatio, nsMgdl: true) == "82bc62b67556f34a")
        #expect(TherapyProfileMath.nightscoutHash([], kind: .carbRatio, nsMgdl: true) == nil)
    }

    @Test("ISF hash vectors: mg/dL form and mmol/L form (contract)")
    func isfVectors() {
        #expect(TherapyProfileMath.isfMgdlHash(TherapyProfileMath.slots(isf1)) == "88ce4c3c77da0c2b")
        #expect(TherapyProfileMath.nightscoutFormHash(isf1, kind: .isf, nsMgdl: true) == "88ce4c3c77da0c2b")
        #expect(TherapyProfileMath.nightscoutFormHash(isf1, kind: .isf, nsMgdl: false) == "2d0d147868c7adf5")
        #expect(TherapyProfileMath.nightscoutFormHash(isf2, kind: .isf, nsMgdl: true) == "4701d2c3453569ad")
        #expect(TherapyProfileMath.nightscoutFormHash(isf2, kind: .isf, nsMgdl: false) == "39a70ffcfeb762f2")
        #expect(TherapyProfileMath.isfMmolHash(tenths: Array(repeating: 26, count: 48)) == "39a70ffcfeb762f2")
        // Nightscout as Trio uploads it: mg/dL values, or asMmolL values (10.0 / 8.3 / 11.1, 2.6).
        #expect(TherapyProfileMath.nightscoutHash([(0, 180), (28800, 150), (79200, 200)], kind: .isf, nsMgdl: true) == "88ce4c3c77da0c2b")
        #expect(TherapyProfileMath.nightscoutHash([(0, 10.0), (28800, 8.3), (79200, 11.1)], kind: .isf, nsMgdl: false) == "2d0d147868c7adf5")
        #expect(TherapyProfileMath.nightscoutHash([(0, 46), (45000, 47)], kind: .isf, nsMgdl: true) == "4701d2c3453569ad")
        #expect(TherapyProfileMath.nightscoutHash([(0, 2.6), (45000, 2.6)], kind: .isf, nsMgdl: false) == "39a70ffcfeb762f2")
        // Exact (Trio internal) slots of ISF2 differ from 47 all day, though the mmol form is the same.
        #expect(TherapyProfileMath.slots(isf2) != TherapyProfileMath.slots(e([("00:00", 47)])))
        #expect(TherapyProfileMath.nightscoutFormHash(e([("00:00", 47)]), kind: .isf, nsMgdl: false) == "39a70ffcfeb762f2")
    }

    // MARK: Units

    @Test("asMmolL tenths (Trio rounding) and mmol/L → mg/dL vectors (contract)")
    func mmolConversion() {
        #expect(TherapyProfileMath.mmolTenths(mgdl: 180) == 100)
        #expect(TherapyProfileMath.mmolTenths(mgdl: 150) == 83) // 8.325 → 8.3
        #expect(TherapyProfileMath.mmolTenths(mgdl: 200) == 111)
        #expect(TherapyProfileMath.mmolTenths(mgdl: 46) == 26 && TherapyProfileMath.mmolTenths(mgdl: 47) == 26)
        let vectors: [(Int, Int)] = [(26, 47), (100, 180), (83, 150), (111, 200), (5, 9), (25, 45), (300, 540)]
        for (tenths, mgdl) in vectors {
            #expect(TherapyProfileMath.mgdl(fromMmolTenths: tenths) == mgdl)
        }
        #expect(TherapyProfileMath.mgdl(fromMmolTenths: 4) == nil)
        #expect(TherapyProfileMath.mgdl(fromMmolTenths: 301) == nil)
        for tenths in 5 ... 300 {
            let mgdl = TherapyProfileMath.mgdl(fromMmolTenths: tenths)
            #expect(mgdl != nil)
            #expect(mgdl.map(TherapyProfileMath.mmolTenths(mgdl:)) == tenths)
        }
    }

    @Test("Nightscout values rounded half-up from the decimal text of the number")
    func halfUp() {
        #expect(TherapyProfileMath.roundedHalfUp(8.25, scale: 10) == 83)
        #expect(TherapyProfileMath.roundedHalfUp(1.15, scale: 10) == 12)
        #expect(TherapyProfileMath.roundedHalfUp(8.3, scale: 10) == 83)
        #expect(TherapyProfileMath.roundedHalfUp(149.5, scale: 1) == 150)
    }

    // MARK: Validation mirror

    @Test("Validation: names, grid, order, ranges")
    func validation() {
        #expect(TherapyProfileMath.validate(name: "Diena", kind: .carbRatio, entries: cr1).isEmpty)
        #expect(TherapyProfileMath.validate(name: "Savaitgalis – žiema", kind: .isf, entries: isf1).isEmpty)
        #expect(!TherapyProfileMath.validate(name: " ", kind: .carbRatio, entries: cr1).isEmpty)
        #expect(!TherapyProfileMath.validate(name: String(repeating: "a", count: 31), kind: .carbRatio, entries: cr1).isEmpty)
        #expect(TherapyProfileMath.validate(name: String(repeating: "Ž", count: 30), kind: .carbRatio, entries: cr1).isEmpty)
        #expect(!TherapyProfileMath.validate(name: "a\"b", kind: .carbRatio, entries: cr1).isEmpty)
        #expect(!TherapyProfileMath.validate(name: "a\nb", kind: .carbRatio, entries: cr1).isEmpty)
        // Entries
        #expect(!TherapyProfileMath.validate(name: "T", kind: .carbRatio, entries: []).isEmpty)
        let all48 = (0 ..< 48).map { TherapyEntry(minutes: $0 * 30, value: 100) }
        #expect(TherapyProfileMath.validate(name: "T", kind: .carbRatio, entries: all48).isEmpty)
        #expect(!TherapyProfileMath.validate(name: "T", kind: .carbRatio, entries: all48 + [TherapyEntry(minutes: 1440, value: 100)]).isEmpty)
        #expect(!TherapyProfileMath.validate(name: "T", kind: .carbRatio, entries: e([("00:30", 100)])).isEmpty) // first not 00:00
        #expect(!TherapyProfileMath.validate(name: "T", kind: .carbRatio, entries: e([("00:00", 100), ("06:15", 90)])).isEmpty)
        #expect(!TherapyProfileMath.validate(name: "T", kind: .carbRatio, entries: e([("00:00", 100), ("06:00", 90), ("06:00", 80)])).isEmpty)
        #expect(!TherapyProfileMath.validate(name: "T", kind: .carbRatio, entries: e([("00:00", 100), ("08:00", 90), ("06:00", 80)])).isEmpty)
        // CR 1.0–50.0
        #expect(TherapyProfileMath.validate(name: "T", kind: .carbRatio, entries: e([("00:00", 10)])).isEmpty)
        #expect(TherapyProfileMath.validate(name: "T", kind: .carbRatio, entries: e([("00:00", 500)])).isEmpty)
        #expect(!TherapyProfileMath.validate(name: "T", kind: .carbRatio, entries: e([("00:00", 9)])).isEmpty)
        #expect(!TherapyProfileMath.validate(name: "T", kind: .carbRatio, entries: e([("00:00", 501)])).isEmpty)
        // ISF 9–540 mg/dL
        #expect(TherapyProfileMath.validate(name: "T", kind: .isf, entries: e([("00:00", 9)])).isEmpty)
        #expect(TherapyProfileMath.validate(name: "T", kind: .isf, entries: e([("00:00", 540)])).isEmpty)
        #expect(!TherapyProfileMath.validate(name: "T", kind: .isf, entries: e([("00:00", 8)])).isEmpty)
        #expect(!TherapyProfileMath.validate(name: "T", kind: .isf, entries: e([("00:00", 541)])).isEmpty)
    }

    @Test("Editor input: CR tenths, ISF mg/dL integers, ISF mmol/L tenths → mg/dL")
    func parsing() {
        #expect(TherapyProfileMath.parse("8.5", kind: .carbRatio, mmol: false) == .success(85))
        #expect(TherapyProfileMath.parse("8,5", kind: .carbRatio, mmol: true) == .success(85))
        #expect(TherapyProfileMath.parse("10", kind: .carbRatio, mmol: false) == .success(100))
        #expect((try? TherapyProfileMath.parse("8.55", kind: .carbRatio, mmol: false).get()) == nil)
        #expect((try? TherapyProfileMath.parse("8.5x", kind: .carbRatio, mmol: false).get()) == nil)
        #expect((try? TherapyProfileMath.parse("", kind: .carbRatio, mmol: false).get()) == nil)
        #expect(TherapyProfileMath.parse("150", kind: .isf, mmol: false) == .success(150))
        #expect((try? TherapyProfileMath.parse("150.5", kind: .isf, mmol: false).get()) == nil)
        #expect(TherapyProfileMath.parse("2.6", kind: .isf, mmol: true) == .success(47))
        #expect(TherapyProfileMath.parse("8.3", kind: .isf, mmol: true) == .success(150))
        #expect(TherapyProfileMath.parse("30.0", kind: .isf, mmol: true) == .success(540))
        #expect((try? TherapyProfileMath.parse("30.1", kind: .isf, mmol: true).get()) == nil)
        #expect((try? TherapyProfileMath.parse("8.35", kind: .isf, mmol: true).get()) == nil)
    }

    @Test("Draft: an unchanged mmol/L text keeps the stored mg/dL; a typed one is converted; 00:00 row always present")
    func draft() {
        let p = TherapyProfile(kind: .isf, name: "ISF2", entries: isf2)
        var draft = TherapyProfileDraft(p, mmol: true)
        #expect(draft.rows.map(\.text) == ["2.6", "2.6"])
        #expect(draft.parsed().entries == isf2) // 46 stays 46
        draft.rows[0].text = "2.6 " // retyped
        #expect(draft.parsed().entries.first?.value == 47)
        let wrapped = TherapyProfileDraft(TherapyProfile(kind: .carbRatio, name: "W", entries: e([("06:00", 80), ("21:00", 120)])), mmol: false)
        #expect(wrapped.rows.first?.minutes == 0 && wrapped.rows.first?.text == "12.0")
        #expect(wrapped.parsed().problems.isEmpty)
        #expect(TherapyProfileMath.slots(wrapped.parsed().entries) == TherapyProfileMath.slots(e([("06:00", 80), ("21:00", 120)])))
        var dup = TherapyProfileDraft(TherapyProfile(kind: .carbRatio, name: "D", entries: cr1), mmol: false)
        dup.rows[2].minutes = 360
        #expect(!dup.parsed().problems.isEmpty)
        #expect(dup.nextFreeMinutes() == 1050)
    }

    // MARK: Nightscout profile parsing

    private func nsProfile(units: String, sens: String) throws -> NSProfile {
        let json = """
        {"defaultProfile":"default","units":"\(units)","store":{"default":{
          "units":"\(units)","timezone":"Europe/Vilnius",
          "basal":[{"time":"00:00","value":0.5,"timeAsSeconds":0}],
          "carbratio":[{"time":"00:00","value":10,"timeAsSeconds":0},{"time":"06:00","value":8.5,"timeAsSeconds":21600},
                       {"time":"11:00","value":12,"timeAsSeconds":39600},{"time":"17:00","value":10.5,"timeAsSeconds":61200}],
          "sens":\(sens)}}}
        """
        return try JSONDecoder().decode(NSProfile.self, from: Data(json.utf8))
    }

    @Test("Nightscout profile in mmol/L (Trio units .mmolL): CR and ISF hashes")
    func nightscoutMmol() throws {
        let profile = try nsProfile(units: "mmol", sens: """
        [{"time":"00:00","value":10,"timeAsSeconds":0},{"time":"08:00","value":8.3,"timeAsSeconds":28800},
         {"time":"22:00","value":11.1,"timeAsSeconds":79200}]
        """)
        let store = try #require(profile.store["default"])
        let cr = ActiveTherapySnapshot(kind: .carbRatio, store: store, loadedAt: 0)
        let isf = ActiveTherapySnapshot(kind: .isf, store: store, loadedAt: 0)
        #expect(cr.hash == "d0f731e0166dbc52")
        #expect(!isf.nsMgdl && isf.isReconstructed)
        #expect(isf.hash == "2d0d147868c7adf5")
        #expect(isf.storedEntries == isf1) // 10.0/8.3/11.1 → 180/150/200
        #expect(cr.storedEntries == cr1)
        #expect(isf.displaySlots(mmol: true)?.first == 100)
        #expect(isf.displaySlots(mmol: false)?.first == 180)
    }

    @Test("Nightscout profile in mg/dL (Trio units .mgdL): ISF hash in the mg/dL form")
    func nightscoutMgdl() throws {
        let profile = try nsProfile(units: "mg/dl", sens: """
        [{"time":"00:00","value":46,"timeAsSeconds":0},{"time":"12:30","value":47,"timeAsSeconds":45000}]
        """)
        let store = try #require(profile.store["default"])
        let isf = ActiveTherapySnapshot(kind: .isf, store: store, loadedAt: 0)
        #expect(isf.nsMgdl && !isf.isReconstructed)
        #expect(isf.hash == "4701d2c3453569ad")
        #expect(isf.storedEntries == isf2)
        #expect(isf.displaySlots(mmol: true) == Array(repeating: 26, count: 48))
        #expect(ActiveTherapySnapshot(kind: .carbRatio, store: store, loadedAt: 0).hash == "d0f731e0166dbc52")
    }

    @Test("Off-grid or out-of-range Nightscout schedules cannot be saved; received text Unknown after 15 min")
    func nightscoutEdgeCases() {
        #expect(TherapyProfileMath.storedEntries(fromNightscout: [(0, 10), (900, 9)], kind: .carbRatio, nsMgdl: true) == nil)
        #expect(TherapyProfileMath.storedEntries(fromNightscout: [(1800, 10)], kind: .carbRatio, nsMgdl: true) == nil)
        #expect(TherapyProfileMath.storedEntries(fromNightscout: [(0, 0.5)], kind: .carbRatio, nsMgdl: true) == nil)
        #expect(TherapyProfileMath.storedEntries(fromNightscout: [(0, 10), (1800, 10)], kind: .carbRatio, nsMgdl: true) == e([("00:00", 100)]))
        let fresh = ActiveTherapySnapshot(kind: .carbRatio, entries: [(0, 10)], nsMgdl: true, loadedAt: 1000)
        #expect(!fresh.receivedText(now: 1000 + 60).hasPrefix("Unknown"))
        #expect(fresh.receivedText(now: 1000 + 16 * 60).hasPrefix("Unknown"))
        #expect(!fresh.isStale(now: 1000 + 15 * 60))
        #expect(ActiveTherapySnapshot(kind: .isf, entries: [(0, 180)], nsMgdl: true, loadedAt: nil).receivedText(now: 1000) == "Unknown")
        #expect(ActiveTherapySnapshot(kind: .isf, entries: [], nsMgdl: true, loadedAt: 1000).receivedText(now: 1000) == "Unknown")
    }

    // MARK: Comparison and safety wording

    @Test("Lower CR / lower ISF = more insulin; > 20 % gets the extra warning with its direction")
    func directionAndWarning() {
        #expect(TherapyProfileMath.direction(now: 100, new: 80) == .more)
        #expect(TherapyProfileMath.direction(now: 100, new: 120) == .less)
        #expect(TherapyProfileMath.InsulinDirection.more.text == "daugiau insulino")
        #expect(TherapyProfileMath.InsulinDirection.less.text == "mažiau insulino")

        let now = TherapyProfileMath.slots(e([("00:00", 100)]))
        let lower = TherapyProfileMath.slots(e([("00:00", 100), ("06:00", 75)]))
        let rows = TherapyProfileMath.comparisonRows(now: now, new: lower)
        #expect(rows.map(\.minutes) == [0, 360])
        let warning = TherapyChange.bigChangeWarning(rows, kind: .carbRatio)
        #expect(warning?.contains("-25 %") == true && warning?.contains("daugiau insulino") == true)
        #expect(TherapyChange.directionLines(rows, kind: .carbRatio).first?.contains("Daugiau insulino (mažesnis CR): 06:00") == true)

        let higher = TherapyProfileMath.slots(e([("00:00", 100), ("06:00", 125)]))
        let rowsUp = TherapyProfileMath.comparisonRows(now: now, new: higher)
        #expect(TherapyChange.bigChangeWarning(rowsUp, kind: .isf)?.contains("mažiau insulino") == true)
        #expect(TherapyChange.directionLines(rowsUp, kind: .isf).first?.contains("Mažiau insulino (didesnis ISF)") == true)

        let small = TherapyProfileMath.comparisonRows(now: now, new: TherapyProfileMath.slots(e([("00:00", 120)])))
        #expect(TherapyChange.bigChangeWarning(small, kind: .carbRatio) == nil) // exactly 20 % is not "more than"
        #expect(TherapyChange.deltaText(small[0], kind: .carbRatio, mmol: false) == "+2.0 (+20 %)")
        #expect(TherapyProfileMath.comparisonRows(now: nil, new: now).count == 1)
        #expect(TherapyChange.directionLines(TherapyProfileMath.comparisonRows(now: now, new: now), kind: .isf) == ["Reikšmės nesikeičia."])
    }

    @Test("Display: ISF in mmol/L shows both units")
    func display() {
        #expect(TherapyProfileMath.fullText(150, kind: .isf, mmol: true) == "8.3 mmol/L (150 mg/dL)")
        #expect(TherapyProfileMath.fullText(150, kind: .isf, mmol: false) == "150 mg/dL")
        #expect(TherapyProfileMath.fullText(85, kind: .carbRatio, mmol: true) == "8.5 g/U")
        #expect(TherapyProfileMath.tenthsText(-15) == "-1.5")
    }

    // MARK: Payload

    private func payload(kind: TherapyKind, entries: [TherapyEntry], name: String) -> CommandPayload {
        CommandPayload(
            user: "LoopFollow", commandType: kind == .carbRatio ? .setCarbRatios : .setISF, timestamp: 1_790_424_000,
            expectedActiveHash: "d0f731e0166dbc52",
            carbRatioSchedule: kind == .carbRatio ? TherapyProfileMath.carbRatioSchedule(entries) : nil,
            isfSchedule: kind == .isf ? TherapyProfileMath.isfSchedule(entries) : nil,
            scheduleName: name,
            returnNotification: .init(
                productionEnvironment: true,
                deviceToken: String(repeating: "a", count: 64), bundleId: "com.B9R54LY699.LoopFollow",
                teamId: "B9R54LY699", keyId: "ABCDEFGHIJ",
                apnsKey: "-----BEGIN PRIVATE KEY-----\n" + String(repeating: "A", count: 200) + "\n-----END PRIVATE KEY-----"
            )
        )
    }

    @Test("set_carb_ratios JSON: carb_ratio_schedule, schedule_name, expected hash; no ISF or basal keys")
    func crJSON() throws {
        let data = try JSONEncoder().encode(payload(kind: .carbRatio, entries: cr1, name: "Diena"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["command_type"] as? String == "set_carb_ratios")
        #expect(json["schedule_name"] as? String == "Diena")
        #expect(json["expected_active_hash"] as? String == "d0f731e0166dbc52")
        let schedule = try #require(json["carb_ratio_schedule"] as? [[String: Any]])
        #expect(schedule.map { $0["start"] as? String } == ["00:00", "06:00", "11:00", "17:00"])
        #expect((schedule[1]["ratio"] as? NSNumber)?.decimalValue == Decimal(string: "8.5"))
        #expect(String(data: data, encoding: .utf8)!.contains("\"ratio\":8.5"))
        #expect(json["isf_schedule"] == nil && json["basal_schedule"] == nil && json["basal_schedule_name"] == nil)
    }

    @Test("set_isf JSON: isf_schedule with integer mg/dL; merged entries; no CR or basal keys")
    func isfJSON() throws {
        let data = try JSONEncoder().encode(payload(kind: .isf, entries: e([("00:00", 180), ("03:00", 180), ("08:00", 150)]), name: "ISF"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["command_type"] as? String == "set_isf")
        let schedule = try #require(json["isf_schedule"] as? [[String: Any]])
        #expect(schedule.map { $0["start"] as? String } == ["00:00", "08:00"])
        #expect(schedule.map { $0["sensitivity"] as? Int } == [180, 150])
        #expect(String(data: data, encoding: .utf8)!.contains("\"sensitivity\":180"))
        #expect(json["carb_ratio_schedule"] == nil && json["basal_schedule"] == nil)
    }

    @Test("Other commands carry none of the new keys")
    func otherCommandsOmitKeys() throws {
        let other = try JSONEncoder().encode(CommandPayload(user: "u", commandType: .cancelOverride, timestamp: 1))
        let json = try #require(JSONSerialization.jsonObject(with: other) as? [String: Any])
        #expect(json["carb_ratio_schedule"] == nil && json["isf_schedule"] == nil && json["schedule_name"] == nil && json["expected_active_hash"] == nil)
        #expect(TRCCommandType.setCarbRatios.rawValue == "set_carb_ratios" && TRCCommandType.setISF.rawValue == "set_isf")
        #expect(EncryptedPushMessage.alertText(commandType: .setCarbRatios, dosingMode: nil) == "Remote Command: Carb Ratios")
        #expect(EncryptedPushMessage.alertText(commandType: .setISF, dosingMode: nil) == "Remote Command: ISF")
    }

    @Test("Whole APNS body < 4 KB with 48 different entries and a 30-character name (CR and ISF)")
    func apnsSize() throws {
        for kind in TherapyKind.allCases {
            let entries = (0 ..< 48).map { TherapyEntry(minutes: $0 * 30, value: kind == .carbRatio ? 453 + $0 : 492 + $0) }
            #expect(TherapyProfileMath.validate(name: "T", kind: kind, entries: entries).isEmpty)
            let count = kind == .carbRatio ? TherapyProfileMath.carbRatioSchedule(entries).count : TherapyProfileMath.isfSchedule(entries).count
            #expect(count == 48)
            let name = String(repeating: "Ž", count: TherapyProfileMath.maxNameLength)
            let messenger = try #require(SecureMessenger(sharedSecret: "test-shared-secret"))
            let encrypted = try messenger.encrypt(payload(kind: kind, entries: entries, name: name))
            let command: TRCCommandType = kind == .carbRatio ? .setCarbRatios : .setISF
            let body = try JSONEncoder().encode(EncryptedPushMessage(encryptedData: encrypted, commandType: command))
            #expect(body.count < 4096)
        }
    }

    // MARK: Storage

    @Test("Storage format and export file round-trip; ids kept; upsert touches only the edited profile")
    func storageRoundTrip() throws {
        let a = TherapyProfile(kind: .carbRatio, name: "A", entries: cr1)
        let b = TherapyProfile(kind: .isf, name: "B", entries: isf2)
        let data = try JSONEncoder().encode([a, b])
        let back = try JSONDecoder().decode([TherapyProfile].self, from: data)
        #expect(back.map(\.id) == [a.id, b.id] && back[0].entries == cr1 && back[1].kind == .isf && back[1].entries == isf2)
        let file = try BasalProfilesDocument.decoder.decode([TherapyProfile].self, from: BasalProfilesDocument.encoder.encode([a]))
        #expect(file.first?.id == a.id && file.first?.name == "A")

        var edited = b
        edited.entries = isf1
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let list = TherapyProfileList.upsert(edited, into: [a, b], now: now)
        #expect(list.map(\.id) == [a.id, b.id] && list[0] == a && list[1].entries == isf1 && list[1].updatedAt == now)
    }

    // MARK: Active marker

    private func original(_ kind: TherapyKind = .carbRatio) -> TherapyProfile {
        TherapyProfile(kind: kind, name: "First", entries: kind == .carbRatio ? cr1 : isf1, createdAt: Date(timeIntervalSince1970: 1000))
    }

    private func copy(of p: TherapyProfile) -> TherapyProfile {
        TherapyProfile(kind: p.kind, name: "First (kopija)", entries: p.entries, createdAt: Date(timeIntervalSince1970: 2000))
    }

    @Test("✓ only on the stored active id while the hash matches; a copy is 'sutampa su aktyviu' and deletable")
    func activeMarker() {
        let a = original()
        let c = copy(of: a)
        let ns = "d0f731e0166dbc52"
        #expect(TherapyActiveMarker.rowState(a, activeID: a.id, nsHash: ns, nsMgdl: false) == .active)
        #expect(TherapyActiveMarker.rowState(c, activeID: a.id, nsHash: ns, nsMgdl: false) == .matchesActive)
        #expect(TherapyActiveMarker.canDelete(c, activeID: a.id) && !TherapyActiveMarker.canDelete(a, activeID: a.id))
        #expect(TherapyActiveMarker.rowState(a, activeID: a.id, nsHash: "eb0120f2d30d1482", nsMgdl: false) == .none)
        #expect(TherapyActiveMarker.rowState(a, activeID: a.id, nsHash: nil, nsMgdl: false) == .none)
        #expect(TherapyActiveMarker.noSavedMatch([a], nsHash: "eb0120f2d30d1482", nsMgdl: false))
        #expect(!TherapyActiveMarker.noSavedMatch([a], nsHash: nil, nsMgdl: false))
        let after = TherapyActiveMarker.afterActivation(sent: c.id, success: true, current: a.id)
        #expect(after == c.id && TherapyActiveMarker.rowState(c, activeID: after, nsHash: ns, nsMgdl: false) == .active)
        #expect(TherapyActiveMarker.afterActivation(sent: c.id, success: false, current: a.id) == a.id)
        #expect(TherapyActiveMarker.matchingProfile([c, a], activeID: nil, nsHash: ns, nsMgdl: false)?.id == a.id)
        #expect(TherapyActiveMarker.matchingProfile([c, a], activeID: c.id, nsHash: ns, nsMgdl: false)?.id == c.id)
        #expect(TherapyActiveMarker.initialActiveID([c, a], storedID: nil, nsHash: ns, nsMgdl: false) == a.id)
        #expect(TherapyActiveMarker.initialActiveID([c, a], storedID: c.id, nsHash: ns, nsMgdl: false) == c.id)
        #expect(TherapyActiveMarker.initialActiveID([c, a], storedID: UUID(), nsHash: ns, nsMgdl: false) == a.id)
    }

    @Test("ISF marker uses the Nightscout form for the profile's units (mmol/L: 46 and 47 mg/dL both match)")
    func isfMarkerUnits() {
        let p = TherapyProfile(kind: .isf, name: "ISF2", entries: isf2)
        #expect(TherapyActiveMarker.rowState(p, activeID: p.id, nsHash: "39a70ffcfeb762f2", nsMgdl: false) == .active)
        #expect(TherapyActiveMarker.rowState(p, activeID: p.id, nsHash: "4701d2c3453569ad", nsMgdl: true) == .active)
        #expect(TherapyActiveMarker.rowState(p, activeID: p.id, nsHash: "39a70ffcfeb762f2", nsMgdl: true) == .none)
        let isf1Profile = original(.isf)
        #expect(TherapyActiveMarker.rowState(isf1Profile, activeID: isf1Profile.id, nsHash: "2d0d147868c7adf5", nsMgdl: false) == .active)
    }

    // MARK: Units end to end

    @Test("ISF 90 mg/dL: sent as \"sensitivity\":90 whatever the app unit; 5.0 mmol/L → 90; confirmation shows both units")
    func isf90EndToEnd() throws {
        let profile = TherapyProfile(kind: .isf, name: "ISF90", entries: e([("00:00", 90)]))
        #expect(TherapyProfileMath.mgdl(fromMmolTenths: 50) == 90 && TherapyProfileMath.mmolTenths(mgdl: 90) == 50)

        for mmol in [false, true] {
            var draft = TherapyProfileDraft(TherapyProfile(kind: .isf, name: "ISF90", entries: e([("00:00", 180)])), mmol: mmol)
            draft.rows[0].text = mmol ? "5.0" : "90"
            #expect(draft.parsed().problems.isEmpty)
            #expect(draft.parsed().entries == profile.entries)
            #expect(TherapyProfileDraft(profile, mmol: mmol).rows[0].text == (mmol ? "5.0" : "90"))

            let payload = CommandPayload(
                user: "u", commandType: .setISF, timestamp: 1, expectedActiveHash: "0000000000000000",
                isfSchedule: TherapyProfileMath.isfSchedule(draft.parsed().entries), scheduleName: "ISF90"
            )
            let text = try #require(String(data: JSONEncoder().encode(payload), encoding: .utf8))
            #expect(text.contains("\"sensitivity\":90"))
            #expect(!text.contains("\"sensitivity\":5") && !text.contains("1620") && !text.contains("0.28"))
        }
        #expect(TherapyChange.scheduleLines(profile, mmol: true).contains("00:00  5.0 mmol/L (90 mg/dL)"))
        #expect(TherapyChange.scheduleLines(profile, mmol: false).contains("00:00  90 mg/dL"))
    }
}

/// Schedule starts are minutes from midnight in Trio's local time and never pass through a TimeZone: the same
/// Nightscout entries give the same entries, slots, hashes and sent start strings in any time zone of this phone.
/// Serialized, and the default time zone is restored afterwards.
@Suite(.serialized)
struct TherapyTimeZoneTests {
    static let zones = ["UTC", "Europe/Vilnius", "Asia/Tokyo", "America/New_York"]

    private func starts(_ payload: CommandPayload, key: String) throws -> [String] {
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        let list = try #require(json[key] as? [[String: Any]])
        return list.compactMap { $0["start"] as? String }
    }

    /// Everything time-related this feature and basal compute from Nightscout, as one comparable text.
    private func signature() throws -> [String] {
        // CR (CR3, 07:30 change) from Nightscout doubles
        let crNS: [(seconds: Int, value: Double)] = [(0, 9.0), (27000, 7.5), (72000, 11.0)]
        let cr = try #require(TherapyProfileMath.storedEntries(fromNightscout: crNS, kind: .carbRatio, nsMgdl: false))
        let crStarts = try starts(
            CommandPayload(user: "u", commandType: .setCarbRatios, timestamp: 1, carbRatioSchedule: TherapyProfileMath.carbRatioSchedule(cr)),
            key: "carb_ratio_schedule"
        )
        // ISF in mmol/L (ISF1) and in mg/dL with a 07:30 change
        let isfNS: [(seconds: Int, value: Double)] = [(0, 10.0), (28800, 8.3), (79200, 11.1)]
        let isfMgdlNS: [(seconds: Int, value: Double)] = [(0, 180), (27000, 150)]
        let isf = try #require(TherapyProfileMath.storedEntries(fromNightscout: isfMgdlNS, kind: .isf, nsMgdl: true))
        let isfStarts = try starts(
            CommandPayload(user: "u", commandType: .setISF, timestamp: 1, isfSchedule: TherapyProfileMath.isfSchedule(isf)),
            key: "isf_schedule"
        )
        // Basal: Trio vector V1 (hourly segments) and V4 (02:30 change)
        let basalV1: [(seconds: Int, rate: Double)] = [
            (0, 0.4), (7200, 0.55), (10800, 0.55), (18000, 0.6), (21600, 0.6), (28800, 0.6),
            (36000, 0.7), (46800, 0.4), (68400, 0.45),
        ]
        let hourly = try #require(BasalProfileMath.hourly(fromNightscout: basalV1))
        let basalStarts = try starts(
            CommandPayload(user: "u", commandType: .setBasalSchedule, timestamp: 1, basalSchedule: BasalProfileMath.segments(hourly)),
            key: "basal_schedule"
        )
        let basalV4: [(seconds: Int, rate: Double)] = [(0, 0.4), (9000, 0.5), (18000, 0.6)]

        #expect(crStarts == ["00:00", "07:30", "20:00"])
        #expect(isfStarts == ["00:00", "07:30"])
        #expect(basalStarts == ["00:00", "02:00", "05:00", "10:00", "13:00", "19:00"])
        #expect(TherapyProfileMath.nightscoutHash(crNS, kind: .carbRatio, nsMgdl: false) == "82bc62b67556f34a")
        #expect(TherapyProfileMath.nightscoutHash(isfNS, kind: .isf, nsMgdl: false) == "2d0d147868c7adf5")
        #expect(BasalProfileMath.hash(ofNightscout: basalV1) == "5c367b5397636149")
        #expect(BasalProfileMath.hash(ofNightscout: basalV4) == "acff0d328fca2e73")

        return [
            crStarts.joined(separator: ","), isfStarts.joined(separator: ","), basalStarts.joined(separator: ","),
            TherapyProfileMath.slots(cr).map(String.init).joined(separator: ","),
            TherapyProfileMath.nightscoutSlots(isfNS, kind: .isf, nsMgdl: false).map(String.init).joined(separator: ","),
            BasalProfileMath.nightscoutSlots(basalV4).map(String.init).joined(separator: ","),
            ActiveTherapySnapshot(kind: .isf, entries: isfNS, nsMgdl: false, loadedAt: 0).hash ?? "",
            ActiveBasalSnapshot(entries: basalV4, loadedAt: 0).hash ?? "",
            TherapyProfileMath.clock(450),
        ]
    }

    @Test("UTC, Vilnius, Tokyo, New York: same entries, slots, hashes and start strings (CR, ISF, basal)")
    func sameInEveryTimeZone() throws {
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        var results: [[String]] = []
        for id in Self.zones {
            NSTimeZone.default = try #require(TimeZone(identifier: id))
            #expect(NSTimeZone.default.identifier == id)
            results.append(try signature())
        }
        #expect(results.count == Self.zones.count)
        #expect(results.allSatisfy { $0 == results[0] })
        #expect(results[0].last == "07:30")
    }
}
