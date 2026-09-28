// LoopFollow
// BasalProfileTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct BasalProfileTests {
    private func d(_ s: String) -> Decimal { Decimal(string: s)! }

    /// Hourly rates from (startHour, rate) steps.
    private func hourly(_ steps: [(Int, String)]) -> [Decimal] {
        (0 ..< 24).map { hour in d(steps.last(where: { $0.0 <= hour })!.1) }
    }

    /// Trio CUSTOMIZATIONS.md §7 vector 1, as Nightscout shows it (entries as stored, with repeats).
    private let vector1NS: [(seconds: Int, rate: Double)] = [
        (0, 0.4), (7200, 0.55), (10800, 0.55), (18000, 0.6), (21600, 0.6), (28800, 0.6),
        (36000, 0.7), (46800, 0.4), (68400, 0.45),
    ]

    // MARK: Hash — must equal Trio

    @Test("Hash of Nightscout entries equals Trio's vectors (CUSTOMIZATIONS.md §7)")
    func trioVectors() {
        #expect(BasalProfileMath.hash(ofNightscout: vector1NS) == "5c367b5397636149") // V1
        #expect(BasalProfileMath.hash(ofNightscout: [(0, 1.0)]) == "946f8ef5ec7fc61e") // V2
        #expect(BasalProfileMath.hash(ofNightscout: [(0, 0.35), (25200, 1.2), (79200, 0.45)]) == "eabd566dccabc3e6") // V3
        #expect(BasalProfileMath.hash(ofNightscout: [(0, 0.4), (9000, 0.5), (18000, 0.6)]) == "acff0d328fca2e73") // V4, 02:30
        #expect(BasalProfileMath.hash(ofNightscout: [(0, 0.4), (7200, 0.55)]) == "b692201fbdc3d38e") // V5
        // V6: not starting at 00:00 — wraps to the last entry; hourly(fromNightscout:) refuses it.
        #expect(BasalProfileMath.hash(ofNightscout: [(21600, 0.5), (72000, 0.3)]) == "69f813145c518801")
        #expect(BasalProfileMath.hash(ofNightscout: [(72000, 0.3), (21600, 0.5)]) == "69f813145c518801")
        #expect(BasalProfileMath.hourly(fromNightscout: [(21600, 0.5), (72000, 0.3)]) == nil)
        #expect(BasalProfileMath.hash(ofNightscout: Array(vector1NS.reversed())) == "5c367b5397636149")
    }

    @Test("Hash depends on the schedule, not on how it is split")
    func hashIgnoresSplitting() {
        // [02:00 0.55, 03:00 0.55] == [02:00 0.55]
        #expect(BasalProfileMath.hash(ofNightscout: [(0, 0.4), (7200, 0.55), (10800, 0.55)]) == "b692201fbdc3d38e")
        // Trio's stored V1 (with repeats) == V1 merged == the same 24 hourly rates.
        let v1Hourly = BasalProfileMath.hourly(fromNightscout: vector1NS)!
        #expect(BasalProfileMath.hash(ofSegments: BasalProfileMath.segments(v1Hourly)) == "5c367b5397636149")
        #expect(BasalProfileMath.hash(ofHourly: v1Hourly) == "5c367b5397636149")
        // 30-minute segments: stable under reordering and redundant entries.
        #expect(BasalProfileMath.hash(ofNightscout: [(18000, 0.6), (0, 0.4), (9000, 0.5), (10800, 0.5)]) == "acff0d328fca2e73")
        #expect(BasalProfileMath.halfHourSlots([(minutes: 0, cents: 40), (minutes: 150, cents: 50)]).count == 48)
    }

    @Test("Hash of the segments this app sends uses the same algorithm")
    func sentSegmentsHash() {
        #expect(BasalProfileMath.hash(ofSegments: BasalProfileMath.segments(Array(repeating: d("1.00"), count: 24))) == "946f8ef5ec7fc61e")
        #expect(BasalProfileMath.hash(ofSegments: BasalProfileMath.segments(hourly([(0, "0.35"), (7, "1.2"), (22, "0.45")]))) == "eabd566dccabc3e6")
        #expect(BasalProfileMath.hash(ofHourly: hourly([(0, "0.4"), (2, "0.55")])) == "b692201fbdc3d38e")
    }

    // MARK: Segments and conversion

    @Test("24 hours merge into segments")
    func merge() {
        let segments = BasalProfileMath.segments(BasalProfileMath.hourly(fromNightscout: vector1NS)!)
        #expect(segments == [
            BasalScheduleSegment(start: "00:00", rate: d("0.4")), BasalScheduleSegment(start: "02:00", rate: d("0.55")),
            BasalScheduleSegment(start: "05:00", rate: d("0.6")), BasalScheduleSegment(start: "10:00", rate: d("0.7")),
            BasalScheduleSegment(start: "13:00", rate: d("0.4")), BasalScheduleSegment(start: "19:00", rate: d("0.45")),
        ])
        #expect(BasalProfileMath.segments(Array(repeating: d("0.5"), count: 24)).count == 1)
        #expect(BasalProfileMath.segments((0 ..< 24).map { Decimal($0 + 1) / 100 }).count == 24)
    }

    @Test("Nightscout schedule to 24 hours; off-hour or late-start schedules are refused")
    func fromNightscout() {
        let h = BasalProfileMath.hourly(fromNightscout: vector1NS)!
        #expect(h.count == 24 && h[0] == d("0.4") && h[4] == d("0.55") && h[12] == d("0.7") && h[23] == d("0.45"))
        #expect(BasalProfileMath.hourly(fromNightscout: [(0, 0.4), (9000, 0.5)]) == nil) // 02:30
        #expect(BasalProfileMath.hourly(fromNightscout: [(3600, 0.4)]) == nil)
        #expect(BasalProfileMath.hourly(fromNightscout: []) == nil)
    }

    // MARK: Validation (same examples as Trio's RemoteBasalScheduleTests)

    @Test("Dana truncation rates are refused, with nearest exact rates", arguments: ["0.29", "1.15", "2.05", "2.30"])
    func danaTruncation(rate: String) {
        var h = Array(repeating: d("0.5"), count: 24)
        h[3] = d(rate)
        let problems = BasalProfileMath.validate(name: "Test", hourly: h)
        #expect(problems.count == 1)
        #expect(problems.first?.text.hasPrefix("03:00 — Dana išsaugotų kitą reikšmę") == true)
        #expect(!BasalProfileMath.nearestExact(d(rate)).isEmpty)
        for near in BasalProfileMath.nearestExact(d(rate)) {
            #expect(BasalProfileMath.danaStoredCents(near) == BasalProfileMath.exactCents(near))
        }
    }

    /// Trio CUSTOMIZATIONS.md §7 "Dana truncation vector": the 65 rates in 0.01–5.00 U/h that Decimal →
    /// Double(truncating:) → UInt16(× 100) stores differently. Trio's own test must produce the same list.
    static let danaTruncatedCents: [Int] = [
        7, 14, 28, 29, 33, 56, 58, 66, 87, 91, 107, 111, 112, 115, 116, 132, 157, 174, 179, 182, 199, 205, 207, 214,
        222, 224, 230, 232, 239, 247, 249, 255, 264, 289, 314, 323, 333, 339, 348, 358, 364, 373, 383, 389, 398, 403,
        410, 414, 419, 423, 428, 435, 439, 444, 448, 453, 460, 464, 469, 473, 478, 485, 489, 494, 498,
    ]

    @Test("Dana truncation table 0.01–5.00 U/h matches Trio's shared vector")
    func danaTruncationTable() {
        var stored: [Int] = []
        var validated: [Int] = []
        for cents in 1 ... 500 {
            let rate = d(String(format: "%d.%02d", cents / 100, cents % 100))
            if BasalProfileMath.danaStoredCents(rate) != cents { stored.append(cents) }
            if !BasalProfileMath.validate(name: "Test", hourly: Array(repeating: rate, count: 24)).isEmpty { validated.append(cents) }
        }
        #expect(stored == Self.danaTruncatedCents)
        #expect(validated == Self.danaTruncatedCents)
    }

    @Test("Everyday rates pass", arguments: ["0.4", "0.45", "0.55", "0.57", "0.6", "0.7", "1.0", "1.1", "1.2"])
    func goodRates(rate: String) {
        #expect(BasalProfileMath.validate(name: "Test", hourly: Array(repeating: d(rate), count: 24)).isEmpty)
    }

    @Test("Zero, sub-hundredth rates and bad names are refused")
    func otherProblems() {
        #expect(!BasalProfileMath.validate(name: "Test", hourly: Array(repeating: 0, count: 24)).isEmpty)
        #expect(!BasalProfileMath.validate(name: "Test", hourly: Array(repeating: d("0.555"), count: 24)).isEmpty)
        #expect(!BasalProfileMath.validate(name: " ", hourly: Array(repeating: d("0.5"), count: 24)).isEmpty)
        #expect(!BasalProfileMath.validate(name: String(repeating: "a", count: 31), hourly: Array(repeating: d("0.5"), count: 24)).isEmpty)
        #expect(!BasalProfileMath.validate(name: "a\"b", hourly: Array(repeating: d("0.5"), count: 24)).isEmpty)
        #expect(!BasalProfileMath.validate(name: "Test", hourly: Array(repeating: d("0.5"), count: 23)).isEmpty)
        #expect(BasalProfileMath.validate(name: "Savaitgalis – žiema", hourly: Array(repeating: d("0.5"), count: 24)).isEmpty)
    }

    // MARK: Totals

    @Test("Daily total and percent change")
    func totals() {
        #expect(BasalProfileMath.dailyTotal(BasalProfileMath.hourly(fromNightscout: vector1NS)!) == d("12.2"))
        #expect(BasalProfileMath.dailyTotal(Array(repeating: d("1"), count: 24)) == 24)
        #expect(BasalProfileMath.percentChange(from: d("12.2"), to: d("12.85")) == 5)
        #expect(BasalProfileMath.percentChange(from: d("10"), to: d("12.5")) == 25)
        #expect(BasalProfileMath.percentChange(from: 0, to: 1) == nil)
    }

    // MARK: Payload

    private func payload(segments: [BasalScheduleSegment], name: String) -> CommandPayload {
        CommandPayload(
            user: "LoopFollow", commandType: .setBasalSchedule, timestamp: 1_790_424_000,
            basalSchedule: segments, basalScheduleName: name, expectedActiveHash: "fd950334d8df0b65",
            returnNotification: .init(
                productionEnvironment: true,
                deviceToken: String(repeating: "a", count: 64), bundleId: "com.B9R54LY699.LoopFollow",
                teamId: "B9R54LY699", keyId: "ABCDEFGHIJ",
                apnsKey: "-----BEGIN PRIVATE KEY-----\n" + String(repeating: "A", count: 200) + "\n-----END PRIVATE KEY-----"
            )
        )
    }

    @Test("JSON: command_type, basal_schedule, name, expected hash; nil fields absent from other commands")
    func json() throws {
        let data = try JSONEncoder().encode(payload(segments: [BasalScheduleSegment(start: "00:00", rate: d("0.55"))], name: "Weekend"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["command_type"] as? String == "set_basal_schedule")
        #expect(json["basal_schedule_name"] as? String == "Weekend")
        #expect(json["expected_active_hash"] as? String == "fd950334d8df0b65")
        let schedule = try #require(json["basal_schedule"] as? [[String: Any]])
        #expect(schedule.first?["start"] as? String == "00:00")
        #expect((schedule.first?["rate"] as? NSNumber)?.decimalValue == d("0.55"))
        #expect(String(data: data, encoding: .utf8)!.contains("\"rate\":0.55"))

        let other = try JSONEncoder().encode(CommandPayload(user: "u", commandType: .cancelOverride, timestamp: 1))
        let otherJSON = try #require(JSONSerialization.jsonObject(with: other) as? [String: Any])
        #expect(otherJSON["basal_schedule"] == nil && otherJSON["basal_schedule_name"] == nil && otherJSON["expected_active_hash"] == nil)
    }

    @Test("Whole APNS body < 4 KB with 24 different segments and the longest name")
    func apnsSize() throws {
        let segments = BasalProfileMath.segments((0 ..< 24).map { Decimal(150 + $0) / 100 })
        #expect(segments.count == 24)
        let name = String(repeating: "Ž", count: BasalProfileMath.maxNameLength)
        let messenger = try #require(SecureMessenger(sharedSecret: "test-shared-secret"))
        let encrypted = try messenger.encrypt(payload(segments: segments, name: name))
        let body = try JSONEncoder().encode(EncryptedPushMessage(encryptedData: encrypted, commandType: .setBasalSchedule))
        #expect(body.count < 4096)
    }

    // MARK: Storage format

    @Test("Profile JSON round-trips")
    func profileRoundTrip() throws {
        let p = BasalProfile(name: "Test", hourlyRates: BasalProfileMath.hourly(fromNightscout: vector1NS)!)
        let data = try BasalProfilesDocument.encoder.encode([p])
        let back = try BasalProfilesDocument.decoder.decode([BasalProfile].self, from: data)
        #expect(back.count == 1 && back[0].hourlyRates == p.hourlyRates && back[0].name == "Test" && back[0].id == p.id)
    }

    @Test("Storage format (plain JSONEncoder/Decoder, as StorageValue) keeps every id; decoding twice gives the same id")
    func storageKeepsIDs() throws {
        let list = [
            BasalProfile(name: "First", hourlyRates: hourly([(0, "0.4")])),
            BasalProfile(name: "Second", hourlyRates: hourly([(0, "0.5")])),
        ]
        let data = try JSONEncoder().encode(list)
        let first = try JSONDecoder().decode([BasalProfile].self, from: data)
        let second = try JSONDecoder().decode([BasalProfile].self, from: data)
        #expect(first.map(\.id) == list.map(\.id))
        #expect(second.map(\.id) == list.map(\.id))
        #expect(first.map(\.name) == ["First", "Second"])
    }

    @Test("Upsert changes only the edited profile; other profiles keep id and content; new profile appended")
    func upsertKeepsOtherIDs() {
        let a = BasalProfile(name: "First", hourlyRates: hourly([(0, "0.4")]))
        let b = BasalProfile(name: "Second", hourlyRates: hourly([(0, "0.5")]))
        var edited = b
        edited.hourlyRates = hourly([(0, "0.6")])
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let afterEdit = BasalProfileList.upsert(edited, into: [a, b], now: now)
        #expect(afterEdit.map(\.id) == [a.id, b.id])
        #expect(afterEdit[0] == a)
        #expect(afterEdit[1].hourlyRates == edited.hourlyRates && afterEdit[1].updatedAt == now)

        let c = BasalProfile(name: "Third", hourlyRates: hourly([(0, "0.7")]))
        let afterAdd = BasalProfileList.upsert(c, into: afterEdit, now: now)
        #expect(afterAdd.map(\.id) == [a.id, b.id, c.id])
        #expect(Array(afterAdd.prefix(2)) == afterEdit)
        #expect(BasalProfileList.profile(id: b.id, in: afterAdd)?.name == "Second")
    }

    // MARK: Active marker

    private func original() -> BasalProfile {
        BasalProfile(name: "First", hourlyRates: hourly([(0, "0.4"), (6, "0.6")]), createdAt: Date(timeIntervalSince1970: 1000))
    }

    private func copy(of p: BasalProfile) -> BasalProfile {
        BasalProfile(name: "First (kopija)", hourlyRates: p.hourlyRates, createdAt: Date(timeIntervalSince1970: 2000))
    }

    @Test("A copy does not get ✓: only the stored active profile does; the copy shows 'sutampa su aktyviu'")
    func copyGetsNoCheckmark() {
        let a = original()
        let c = copy(of: a)
        let ns = BasalProfileMath.hash(ofHourly: a.hourlyRates)
        #expect(BasalActiveMarker.rowState(a, activeID: a.id, nsHash: ns) == .active)
        #expect(BasalActiveMarker.rowState(c, activeID: a.id, nsHash: ns) == .matchesActive)
        #expect(!BasalActiveMarker.noSavedMatch([a, c], nsHash: ns))
    }

    @Test("The copy can be deleted; the stored active profile cannot")
    func copyCanBeDeleted() {
        let a = original()
        let c = copy(of: a)
        #expect(BasalActiveMarker.canDelete(c, activeID: a.id))
        #expect(!BasalActiveMarker.canDelete(a, activeID: a.id))
    }

    @Test("Active id switches to the activated profile on a successful send, stays on a failed one")
    func activeIDSwitchesAfterActivation() {
        let a = original()
        let c = copy(of: a)
        let ns = BasalProfileMath.hash(ofHourly: a.hourlyRates)
        let after = BasalActiveMarker.afterActivation(sent: c.id, success: true, current: a.id)
        #expect(after == c.id)
        #expect(BasalActiveMarker.rowState(c, activeID: after, nsHash: ns) == .active)
        #expect(BasalActiveMarker.rowState(a, activeID: after, nsHash: ns) == .matchesActive)
        #expect(BasalActiveMarker.canDelete(a, activeID: after))
        #expect(BasalActiveMarker.afterActivation(sent: c.id, success: false, current: a.id) == a.id)
    }

    @Test("Nightscout schedule not equal to the active profile removes ✓; note when no saved profile matches")
    func hashMismatchRemovesCheckmark() {
        let a = original()
        let other = BasalProfileMath.hash(ofHourly: hourly([(0, "0.5")]))
        #expect(BasalActiveMarker.rowState(a, activeID: a.id, nsHash: other) == .none)
        #expect(BasalActiveMarker.noSavedMatch([a], nsHash: other))
        #expect(BasalActiveMarker.rowState(a, activeID: a.id, nsHash: nil) == .none)
        #expect(!BasalActiveMarker.noSavedMatch([a], nsHash: nil))
    }

    @Test("Without a stored active id the oldest profile with Nightscout's schedule is chosen; a stored id is kept")
    func initialActiveID() {
        let a = original()
        let c = copy(of: a)
        let ns = BasalProfileMath.hash(ofHourly: a.hourlyRates)
        #expect(BasalActiveMarker.initialActiveID([c, a], storedID: nil, nsHash: ns) == a.id)
        #expect(BasalActiveMarker.initialActiveID([c, a], storedID: c.id, nsHash: ns) == c.id)
        #expect(BasalActiveMarker.initialActiveID([c, a], storedID: UUID(), nsHash: ns) == a.id) // deleted id replaced
        #expect(BasalActiveMarker.initialActiveID([a], storedID: nil, nsHash: "0000000000000000") == nil)
    }
}
