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

    @Test("Hash of Nightscout entries equals Trio's vectors")
    func trioVectors() {
        #expect(BasalProfileMath.hash(ofNightscout: vector1NS) == "fd950334d8df0b65")
        #expect(BasalProfileMath.hash(ofNightscout: [(0, 1.0)]) == "cb753f988e32a89d")
        #expect(BasalProfileMath.hash(ofNightscout: [(0, 0.35), (25200, 1.2), (79200, 0.45)]) == "aa5480f602dbc4d4")
        #expect(BasalProfileMath.hash(ofNightscout: Array(vector1NS.reversed())) == "fd950334d8df0b65")
    }

    @Test("Hash of the segments this app sends uses the same algorithm")
    func sentSegmentsHash() {
        #expect(BasalProfileMath.hash(ofSegments: BasalProfileMath.segments(Array(repeating: d("1.00"), count: 24))) == "cb753f988e32a89d")
        #expect(BasalProfileMath.hash(ofSegments: BasalProfileMath.segments(hourly([(0, "0.35"), (7, "1.2"), (22, "0.45")]))) == "aa5480f602dbc4d4")
        // Merged vector 1 ("0:40;120:55;300:60;600:70;780:40;1140:45") differs from Trio's stored form with repeats.
        #expect(BasalProfileMath.hash(ofSegments: BasalProfileMath.segments(BasalProfileMath.hourly(fromNightscout: vector1NS)!)) == "031372d0b50f4a30")
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
}
