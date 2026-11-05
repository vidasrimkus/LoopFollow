// LoopFollow
// TherapyCommandStatus.swift

import Combine
import Foundation
import SwiftUI

/// Persisted per kind: APNS acceptance never marks a schedule as applied.
final class TherapyCommandStatus: ObservableObject {
    static let shared = TherapyCommandStatus()
    static let storageKey = "TherapyCommandStatus.v1"

    enum Phase: String, Codable { case sending, sent, applied, rejected, failed }

    struct Record: Codable, Equatable {
        let id: UUID
        let command: String
        let profileID: UUID?
        let startedAt: Date
        var phase: Phase
        var message: String?

        func isPending(now: Date) -> Bool {
            (phase == .sending || phase == .sent) && now.timeIntervalSince(startedAt) < 300
        }

        func text(now: Date) -> String {
            switch phase {
            case .sending, .sent:
                if now.timeIntervalSince(startedAt) >= 300 { return "Trio neatsakė – patikrink vaiko telefoną. Komanda dar gali būti pristatyta." }
                return phase == .sending ? "Siunčiama…" : "Išsiųsta. Laukiama Trio atsakymo…"
            case .applied: return "Trio pritaikė: " + (message ?? "grafikas atnaujintas")
            case .rejected: return "Trio atmetė: " + (message ?? "nežinoma priežastis")
            case .failed: return "Siuntimo klaida: " + (message ?? "nežinoma priežastis")
            }
        }
    }

    private let defaults: UserDefaults
    @Published private(set) var records: [String: Record] {
        didSet { if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.storageKey) } }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:]
    }

    func record(_ kind: TherapyKind) -> Record? { records[kind.rawValue] }

    @discardableResult func begin(kind: TherapyKind, command: TRCCommandType, profileID: UUID? = nil, now: Date = Date()) -> UUID {
        let id = UUID()
        records[kind.rawValue] = Record(id: id, command: command.rawValue, profileID: profileID, startedAt: now, phase: .sending)
        return id
    }

    func sent(kind: TherapyKind, id: UUID, success: Bool, error: String?) {
        guard var record = record(kind), record.id == id, record.phase == .sending else { return }
        record.phase = success ? .sent : .failed
        record.message = error
        records[kind.rawValue] = record
    }

    /// Only a correlated response for the latest operation may update the UI. Old/other pushes are ignored.
    @discardableResult func receive(_ userInfo: [AnyHashable: Any]) -> TherapyKind? {
        guard let raw = userInfo["command_id"] as? String, let id = UUID(uuidString: raw),
              let command = userInfo["command_type"] as? String,
              let status = userInfo["command_status"] as? String, ["success", "failed"].contains(status)
        else { return nil }
        for kind in TherapyKind.allCases {
            guard var record = record(kind), record.id == id, record.command == command,
                  record.phase != .applied, record.phase != .rejected else { continue }
            let aps = userInfo["aps"] as? [String: Any]
            let alert = aps?["alert"] as? [String: Any]
            record.phase = status == "success" ? .applied : .rejected
            record.message = alert?["body"] as? String
            records[kind.rawValue] = record
            return kind
        }
        return nil
    }

    static func handle(_ userInfo: [AnyHashable: Any]) {
        DispatchQueue.main.async {
            let tracker = Self.shared
            guard let kind = tracker.receive(userInfo), let record = tracker.record(kind), record.phase == .applied else { return }
            kind.activeID.value = record.profileID
            TaskScheduler.shared.rescheduleTask(id: .profile, to: Date())
        }
    }
}

struct TherapyCommandStatusView: View {
    let kind: TherapyKind
    @ObservedObject private var status = TherapyCommandStatus.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            if let record = status.record(kind) {
                Text(record.text(now: context.date)).font(.callout)
            }
        }
    }
}

struct RestorePreviousTherapyView: View {
    let kind: TherapyKind
    @ObservedObject private var status = TherapyCommandStatus.shared
    @State private var showConfirmation = false
    @State private var expectedHash: String?
    @State private var error: String?

    var body: some View {
        Section(header: Text("Atkūrimas Trio telefone")) {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                Button("Grąžinti ankstesnį \(kind.shortName)") {
                    expectedHash = ActiveTherapySnapshot.current(kind).hash
                    if expectedHash == nil { error = "Pirma atnaujink Nightscout profilį." } else { showConfirmation = true }
                }
                .disabled(status.record(kind)?.isPending(now: context.date) == true)
            }
            Text("Atkuriama tiksli paskutinė prieš nuotolinį pakeitimą Trio telefone išsaugota kopija. ±20 % riba atkūrimui netaikoma.")
                .font(.caption).foregroundColor(.secondary)
            if let error { Text(error).foregroundColor(.red) }
            TherapyCommandStatusView(kind: kind)
        }
        .alert("Grąžinti ankstesnį \(kind.shortName)?", isPresented: $showConfirmation) {
            Button("Grąžinti", role: .destructive) { restore() }
            Button("Atšaukti", role: .cancel) {}
        } message: {
            Text("Trio atstatys tik savo telefone saugomą ankstesnį grafiką. Šiame telefone jo reikšmių peržiūrėti negalima. Jei aktyvus grafikas pasikeitė, komanda bus atmesta.")
        }
    }

    private func restore() {
        guard let expectedHash else { return }
        let command: TRCCommandType = kind == .carbRatio ? .restorePreviousCarbRatios : .restorePreviousISF
        let id = status.begin(kind: kind, command: command)
        PushNotificationManager().sendRestoreTherapyPushNotification(kind: kind, expectedActiveHash: expectedHash, commandID: id) { success, error in
            DispatchQueue.main.async { status.sent(kind: kind, id: id, success: success, error: error) }
        }
    }
}
