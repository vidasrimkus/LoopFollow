// LoopFollow
// BasalProfilesView.swift

import SwiftUI
import UniformTypeIdentifiers

/// Trio's active basal schedule as this phone last loaded it from Nightscout (store.default.basal).
struct ActiveBasalSnapshot {
    let entries: [(seconds: Int, rate: Double)]
    let loadedAt: TimeInterval?

    static let staleAfter: TimeInterval = 15 * 60

    static func current() -> ActiveBasalSnapshot {
        ActiveBasalSnapshot(
            entries: ProfileManager.shared.basalSchedule.map { (seconds: $0.timeAsSeconds, rate: $0.value) },
            loadedAt: Observable.shared.nsProfileLoadedAt.value
        )
    }

    var hourly: [Decimal]? { BasalProfileMath.hourly(fromNightscout: entries) }
    var hash: String? { entries.isEmpty ? nil : BasalProfileMath.hash(ofNightscout: entries) }
    var total: Decimal? { hourly.map(BasalProfileMath.dailyTotal) }

    func isStale(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let loadedAt, !entries.isEmpty else { return true }
        return now - loadedAt > Self.staleAfter
    }

    func ageText(now: TimeInterval = Date().timeIntervalSince1970) -> String {
        guard let loadedAt else { return "duomenų nėra" }
        return "prieš \(max(0, Int((now - loadedAt) / 60))) min"
    }
}

enum BasalProfileFormat {
    static func rate(_ value: Decimal) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        return String(format: "%.2f", NSDecimalNumber(decimal: rounded).doubleValue)
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}

/// Export/import file: the saved profiles as JSON.
struct BasalProfilesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var profiles: [BasalProfile]

    init(profiles: [BasalProfile]) { self.profiles = profiles }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        profiles = try Self.decoder.decode([BasalProfile].self, from: data)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encoder.encode(profiles))
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

struct BasalProfilesView: View {
    @ObservedObject private var profiles = Storage.shared.basalProfiles
    @ObservedObject private var loadedAt = Observable.shared.nsProfileLoadedAt
    @ObservedObject private var device = Storage.shared.device

    @State private var editing: BasalProfile?
    @State private var showSaveCurrent = false
    @State private var newName = ""
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var message: String?

    private var active: ActiveBasalSnapshot { ActiveBasalSnapshot.current() }

    var body: some View {
        Form {
            if device.value != "Trio" {
                Text("Remote commands are currently only available for Trio.").foregroundColor(.secondary)
            }
            Section(header: Text("Dabartinis Trio grafikas (Nightscout)")) {
                if let total = active.total {
                    HStack { Text("Paros suma"); Spacer(); Text("\(BasalProfileFormat.rate(total)) U/d").foregroundColor(.secondary) }
                } else if !active.entries.isEmpty {
                    Text("Grafikas turi segmentų ne nuo sveikos valandos — jo negalima išsaugoti kaip profilio.").foregroundColor(.orange)
                } else {
                    Text("Nightscout profilio dar nėra.").foregroundColor(.secondary)
                }
                HStack { Text("Duomenys"); Spacer(); Text(active.ageText()).foregroundColor(active.isStale() ? .orange : .secondary) }
                Button("Išsaugoti dabartinį kaip…") {
                    newName = ""
                    showSaveCurrent = true
                }
                .disabled(active.hourly == nil)
            }

            Section(header: Text("Profiliai")) {
                if profiles.value.isEmpty {
                    Text("Išsaugotų profilių nėra.").foregroundColor(.secondary)
                }
                ForEach(profiles.value) { profile in
                    let isActive = active.hourly == profile.hourlyRates
                    NavigationLink(destination: BasalProfileActivationView(profile: profile)) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(profile.name).font(.headline)
                                Text("\(BasalProfileFormat.rate(BasalProfileMath.dailyTotal(profile.hourlyRates))) U/d")
                                    .font(.subheadline).foregroundColor(.secondary)
                            }
                            Spacer()
                            if isActive { Image(systemName: "checkmark").foregroundColor(.green) }
                        }
                    }
                    .swipeActions {
                        Button("Redaguoti") { editing = profile }.tint(.blue)
                        Button("Kopijuoti") { copy(profile) }.tint(.gray)
                        if !isActive {
                            Button("Trinti", role: .destructive) { delete(profile) }
                        }
                    }
                }
            }

            Section {
                Button("Naujas profilis") {
                    editing = BasalProfile(name: "", hourlyRates: active.hourly ?? Array(repeating: Decimal(string: "0.5")!, count: 24))
                }
                Button("Eksportuoti (JSON)") { showExporter = true }.disabled(profiles.value.isEmpty)
                Button("Importuoti (JSON)") { showImporter = true }
            }
        }
        .navigationTitle("Basal Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { TaskScheduler.shared.rescheduleTask(id: .profile, to: Date()) }
        .sheet(item: $editing) { profile in
            BasalProfileEditorView(profile: profile) { saved in upsert(saved) }
        }
        .alert("Išsaugoti dabartinį kaip", isPresented: $showSaveCurrent) {
            TextField("Pavadinimas", text: $newName)
            Button("Išsaugoti") { saveCurrent(named: newName) }
            Button("Atšaukti", role: .cancel) {}
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .fileExporter(isPresented: $showExporter, document: BasalProfilesDocument(profiles: profiles.value),
                      contentType: .json, defaultFilename: "basal-profiles") { result in
            if case let .failure(error) = result { message = "Eksportas nepavyko: \(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in importProfiles(result) }
    }

    // MARK: - Actions

    private func upsert(_ profile: BasalProfile) {
        var list = profiles.value
        var updated = profile
        updated.updatedAt = Date()
        if let i = list.firstIndex(where: { $0.id == profile.id }) { list[i] = updated } else { list.append(updated) }
        profiles.value = list
    }

    private func copy(_ profile: BasalProfile) {
        let name = String("\(profile.name) (kopija)".prefix(BasalProfileMath.maxNameLength))
        profiles.value.append(BasalProfile(name: name, hourlyRates: profile.hourlyRates))
    }

    private func delete(_ profile: BasalProfile) {
        guard active.hourly != profile.hourlyRates else { return } // the active one is never deleted
        profiles.value.removeAll { $0.id == profile.id }
    }

    private func saveCurrent(named name: String) {
        guard let hourly = active.hourly else { return }
        let problems = BasalProfileMath.validate(name: name, hourly: hourly).filter {
            if case .name = $0 { return true } else { return false }
        }
        guard problems.isEmpty else { message = problems.map(\.text).joined(separator: "\n"); return }
        profiles.value.append(BasalProfile(name: name.trimmingCharacters(in: .whitespaces), hourlyRates: hourly))
    }

    private func importProfiles(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let imported = try BasalProfilesDocument.decoder.decode([BasalProfile].self, from: Data(contentsOf: url))
                .filter { $0.hourlyRates.count == BasalProfileMath.hours }
            var list = profiles.value
            var added = 0
            for p in imported where !list.contains(where: { $0.id == p.id || ($0.name == p.name && $0.hourlyRates == p.hourlyRates) }) {
                list.append(p)
                added += 1
            }
            profiles.value = list
            message = "Importuota profilių: \(added)."
        } catch {
            message = "Importas nepavyko: \(error.localizedDescription)"
        }
    }
}

// MARK: - Editor

struct BasalProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var texts: [String]
    private let original: BasalProfile
    private let onSave: (BasalProfile) -> Void

    init(profile: BasalProfile, onSave: @escaping (BasalProfile) -> Void) {
        original = profile
        self.onSave = onSave
        _name = State(initialValue: profile.name)
        _texts = State(initialValue: profile.hourlyRates.map(BasalProfileFormat.rate))
    }

    private var hourly: [Decimal] {
        texts.map { Decimal(string: $0.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
    }

    private var problems: [BasalProfileMath.Problem] { BasalProfileMath.validate(name: name, hourly: hourly) }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Pavadinimas")) { TextField("Pavadinimas", text: $name) }
                Section(header: Text("Paros suma: \(BasalProfileFormat.rate(BasalProfileMath.dailyTotal(hourly))) U/d")) {
                    ForEach(0 ..< BasalProfileMath.hours, id: \.self) { hour in
                        HStack {
                            Text(String(format: "%02d:00", hour)).monospacedDigit()
                            Spacer()
                            TextField("U/h", text: $texts[hour])
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("U/h").foregroundColor(.secondary)
                        }
                    }
                }
                if !problems.isEmpty {
                    Section(header: Text("Klaidos")) {
                        ForEach(problems.map(\.text), id: \.self) { Text($0).foregroundColor(.red) }
                    }
                }
            }
            .navigationTitle(original.name.isEmpty ? "Naujas profilis" : "Redaguoti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Atšaukti") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Išsaugoti") {
                        var saved = original
                        saved.name = name.trimmingCharacters(in: .whitespaces)
                        saved.hourlyRates = hourly
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(!problems.isEmpty)
                }
            }
        }
    }
}

// MARK: - Activation

struct BasalProfileActivationView: View {
    let profile: BasalProfile
    private let pushNotificationManager = PushNotificationManager()

    @ObservedObject private var profiles = Storage.shared.basalProfiles
    @State private var showConfirm = false
    @State private var confirmText = ""
    @State private var frozenHash: String?
    @State private var isSending = false
    @State private var result: String?
    @State private var lastSent: (profile: BasalProfile, hash: String)?

    private var active: ActiveBasalSnapshot { ActiveBasalSnapshot.current() }

    var body: some View {
        Form {
            let current = active.hourly
            let oldTotal = current.map(BasalProfileMath.dailyTotal)
            let newTotal = BasalProfileMath.dailyTotal(profile.hourlyRates)
            Section(header: Text("Paros suma")) {
                Text(summary(old: oldTotal, new: newTotal))
                if active.isStale() {
                    Text("⚠️ Nightscout profilio duomenys \(active.ageText()) — aktyvus grafikas gali būti kitas.").foregroundColor(.orange)
                }
            }
            Section(header: Text("Valanda | dabar | naujas | Δ")) {
                ForEach(0 ..< BasalProfileMath.hours, id: \.self) { hour in
                    let now = current?[hour]
                    let new = profile.hourlyRates[hour]
                    HStack {
                        Text(String(format: "%02d:00", hour)).monospacedDigit()
                        Spacer()
                        Text(now.map(BasalProfileFormat.rate) ?? "—").frame(width: 50, alignment: .trailing).foregroundColor(.secondary)
                        Text(BasalProfileFormat.rate(new)).frame(width: 50, alignment: .trailing)
                        Text(now.map { delta(new - $0) } ?? "").frame(width: 55, alignment: .trailing)
                            .foregroundColor(now.map { $0 == new } ?? true ? .secondary : .orange)
                    }.monospacedDigit()
                }
            }
            let problems = BasalProfileMath.validate(name: profile.name, hourly: profile.hourlyRates)
            if !problems.isEmpty {
                Section(header: Text("Negalima siųsti")) {
                    ForEach(problems.map(\.text), id: \.self) { Text($0).foregroundColor(.red) }
                }
            }
            Section {
                Button("Aktyvuoti") { prepareConfirmation(old: oldTotal, new: newTotal) }
                    .disabled(isSending || !problems.isEmpty || active.hash == nil)
                if lastSent != nil {
                    Button("Kartoti (siųsti tą patį)") { if let last = lastSent { send(last.profile, hash: last.hash) } }
                        .disabled(isSending)
                }
                if let result { Text(result).foregroundColor(.secondary) }
            }
            if isSending { ProgressView("Siunčiama…") }
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { TaskScheduler.shared.rescheduleTask(id: .profile, to: Date()) }
        .alert("Aktyvuoti bazalo profilį", isPresented: $showConfirm) {
            Button("Aktyvuoti", role: .destructive) {
                if let hash = frozenHash { activate(hash: hash) }
            }
            Button("Atšaukti", role: .cancel) {}
        } message: {
            Text(confirmText)
        }
    }

    private func summary(old: Decimal?, new: Decimal) -> String {
        guard let old else { return "? → \(BasalProfileFormat.rate(new)) U/d" }
        let pct = BasalProfileMath.percentChange(from: old, to: new).map { String(format: " (%+d %%)", $0) } ?? ""
        return "\(BasalProfileFormat.rate(old)) → \(BasalProfileFormat.rate(new)) U/d\(pct)"
    }

    private func delta(_ d: Decimal) -> String {
        d == 0 ? "0" : (d > 0 ? "+" : "") + BasalProfileFormat.rate(d)
    }

    /// Text and expected hash are fixed here, when the dialog opens, and not recomputed while it is shown.
    private func prepareConfirmation(old: Decimal?, new: Decimal) {
        var text = "\(profile.name)\n\(summary(old: old, new: new))\nTrio įrašys grafiką į pompą (tik Dana)."
        if let old, let pct = BasalProfileMath.percentChange(from: old, to: new), abs(pct) > 20 {
            text += "\n\n⚠️ Paros suma keičiasi daugiau nei 20 % (\(pct > 0 ? "+" : "")\(pct) %)."
        }
        if active.isStale() {
            text += "\n\n⚠️ Nightscout duomenys \(active.ageText()): Trio gali atmesti komandą, jei aktyvus grafikas pasikeitė."
        }
        if active.hourly == nil {
            text += "\n\nDabartinio grafiko negalima automatiškai išsaugoti kaip „Ankstesnis“ (ne sveikos valandos)."
        }
        confirmText = text
        frozenHash = active.hash
        showConfirm = true
    }

    private func activate(hash: String) {
        saveCurrentAsPrevious()
        send(profile, hash: hash)
    }

    /// Before every activation the schedule being replaced is kept as "Ankstesnis (YYYY-MM-DD HH:MM)", unless a
    /// saved profile with the same 24 rates already exists.
    private func saveCurrentAsPrevious() {
        guard let hourly = active.hourly, !profiles.value.contains(where: { $0.hourlyRates == hourly }) else { return }
        profiles.value.append(BasalProfile(name: "Ankstesnis (\(BasalProfileFormat.stamp(Date())))", hourlyRates: hourly))
    }

    private func send(_ profile: BasalProfile, hash: String) {
        isSending = true
        lastSent = (profile, hash)
        pushNotificationManager.sendBasalSchedulePushNotification(profile: profile, expectedActiveHash: hash) { success, error in
            DispatchQueue.main.async {
                isSending = false
                result = success
                    ? RemoteCommandMessage.sent + " Jei Trio praneš pompos klaidą, spauskite „Kartoti“ — tas pats siuntimas saugus."
                    : "Klaida: \(error ?? "nežinoma")"
                LogManager.shared.log(category: .apns, message: "sendBasalSchedulePushNotification \(success ? "succeeded" : "failed") for \(profile.name)")
            }
        }
    }
}
