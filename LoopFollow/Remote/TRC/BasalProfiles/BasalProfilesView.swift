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

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
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
        try FileWrapper(regularFileWithContents: Self.encoder.encode(profiles))
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

/// Activation opened for one saved profile (by id), with the active schedule and time taken at the tap.
struct BasalActivationRequest: Identifiable {
    let id: UUID
    let snapshot: ActiveBasalSnapshot
    let capturedAt: Date
}

/// The editor's unsaved values. Nothing is written to Storage until "Išsaugoti".
struct BasalProfileDraft: Identifiable {
    let original: BasalProfile
    var name: String
    var texts: [String]

    var id: UUID { original.id }

    init(_ profile: BasalProfile) {
        original = profile
        name = profile.name
        texts = profile.hourlyRates.map(BasalProfileFormat.rate)
    }
}

/// Which Basal Profiles sheet is open, and the editor draft — kept outside the views. The Remote screens are
/// redrawn on every devicestatus fetch (`Storage.device` publishes even when unchanged), and a screen held in the
/// pushed list's own @State was closed within seconds; state here survives any redraw or re-creation of the list.
final class BasalProfilesUIState: ObservableObject {
    static let shared = BasalProfilesUIState()

    @Published var activation: BasalActivationRequest?
    @Published var editing: BasalProfileDraft?
}

struct BasalProfilesView: View {
    @ObservedObject private var profiles = Storage.shared.basalProfiles
    @ObservedObject private var device = Storage.shared.device
    @ObservedObject private var ui = BasalProfilesUIState.shared
    @ObservedObject private var activeID = Storage.shared.activeBasalProfileID

    @State private var showSaveCurrent = false
    @State private var newName = ""
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var message: String?

    /// Nightscout's active schedule, taken when the screen appears or on "Atnaujinti" — not observed live, so a
    /// Nightscout or devicestatus update never redraws this screen under an open editor or activation.
    @State private var active = ActiveBasalSnapshot.current()

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
                Button("Atnaujinti") {
                    TaskScheduler.shared.rescheduleTask(id: .profile, to: Date())
                    active = ActiveBasalSnapshot.current()
                }
                Button("Išsaugoti dabartinį kaip…") {
                    newName = ""
                    showSaveCurrent = true
                }
                .disabled(active.hourly == nil)
            }

            if BasalActiveMarker.noSavedMatch(profiles.value, nsHash: active.hash) {
                Section {
                    Text("Aktyvus grafikas pompoje neatitinka nė vieno išsaugoto profilio.").foregroundColor(.orange)
                    Button("Išsaugoti dabartinį kaip…") {
                        newName = ""
                        showSaveCurrent = true
                    }
                    .disabled(active.hourly == nil)
                }
            }

            Section(header: Text("Profiliai")) {
                if profiles.value.isEmpty {
                    Text("Išsaugotų profilių nėra.").foregroundColor(.secondary)
                }
                ForEach(profiles.value) { profile in
                    let state = BasalActiveMarker.rowState(profile, activeID: activeID.value, nsHash: active.hash)
                    // Tap on the name opens the editor; "Aktyvuoti" and the "…" menu are separate buttons in the row
                    // (borderless styles, so each takes only its own taps).
                    HStack {
                        Button { ui.editing = BasalProfileDraft(profile) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name).font(.headline)
                                    Text("\(BasalProfileFormat.rate(BasalProfileMath.dailyTotal(profile.hourlyRates))) U/d")
                                        .font(.subheadline).foregroundColor(.secondary)
                                    if state == .matchesActive {
                                        Text("sutampa su aktyviu").font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if state == .active { Image(systemName: "checkmark").foregroundColor(.green) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.primary)

                        Button("Aktyvuoti") {
                            ui.activation = BasalActivationRequest(id: profile.id, snapshot: ActiveBasalSnapshot.current(), capturedAt: Date())
                        }
                        .buttonStyle(.bordered)

                        Menu {
                            Button("Kopijuoti") { copy(profile) }
                            Button("Trinti", role: .destructive) { delete(profile) }
                                .disabled(!BasalActiveMarker.canDelete(profile, activeID: activeID.value))
                        } label: {
                            Image(systemName: "ellipsis.circle").imageScale(.large)
                        }
                        .buttonStyle(.borderless)
                    }
                    .swipeActions {
                        Button("Redaguoti") { ui.editing = BasalProfileDraft(profile) }.tint(.blue)
                        Button("Kopijuoti") { copy(profile) }.tint(.gray)
                        if BasalActiveMarker.canDelete(profile, activeID: activeID.value) {
                            Button("Trinti", role: .destructive) { delete(profile) }
                        }
                    }
                }
            }

            Section {
                Button("Naujas profilis") {
                    ui.editing = BasalProfileDraft(
                        BasalProfile(name: "", hourlyRates: active.hourly ?? Array(repeating: Decimal(string: "0.5")!, count: 24))
                    )
                }
                Button("Eksportuoti (JSON)") { showExporter = true }.disabled(profiles.value.isEmpty)
                Button("Importuoti (JSON)") { showImporter = true }
            }
        }
        .navigationTitle("Basal Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            TaskScheduler.shared.rescheduleTask(id: .profile, to: Date())
            active = ActiveBasalSnapshot.current()
            let initial = BasalActiveMarker.initialActiveID(profiles.value, storedID: activeID.value, nsHash: active.hash)
            if initial != activeID.value { activeID.value = initial }
        }
        .sheet(item: $ui.editing) { _ in
            BasalProfileEditorView(ui: ui) { saved in upsert(saved) }
                .interactiveDismissDisabled() // only "Atšaukti" / "Išsaugoti" close it; a swipe would lose the draft
        }
        .sheet(item: $ui.activation) { request in
            NavigationStack {
                Group {
                    if let profile = BasalProfileList.profile(id: request.id, in: profiles.value) {
                        BasalProfileActivationView(profile: profile, active: request.snapshot, capturedAt: request.capturedAt)
                    } else {
                        Text("Profilis ištrintas.").foregroundColor(.secondary)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Uždaryti") { ui.activation = nil } }
                }
            }
        }
        .alert("Išsaugoti dabartinį kaip", isPresented: $showSaveCurrent) {
            TextField("Pavadinimas", text: $newName)
            Button("Išsaugoti") { saveCurrent(named: newName) }
            Button("Atšaukti", role: .cancel) {}
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .fileExporter(
            isPresented: $showExporter,
            document: BasalProfilesDocument(profiles: profiles.value),
            contentType: .json,
            defaultFilename: "basal-profiles"
        ) { result in
            if case let .failure(error) = result { message = "Eksportas nepavyko: \(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in importProfiles(result) }
    }

    // MARK: - Actions

    private func upsert(_ profile: BasalProfile) {
        profiles.value = BasalProfileList.upsert(profile, into: profiles.value)
    }

    private func copy(_ profile: BasalProfile) {
        let name = String("\(profile.name) (kopija)".prefix(BasalProfileMath.maxNameLength))
        profiles.value.append(BasalProfile(name: name, hourlyRates: profile.hourlyRates))
    }

    private func delete(_ profile: BasalProfile) {
        guard BasalActiveMarker.canDelete(profile, activeID: activeID.value) else { return } // never the active one
        profiles.value.removeAll { $0.id == profile.id }
    }

    private func saveCurrent(named name: String) {
        guard let hourly = active.hourly else { return }
        let problems = BasalProfileMath.validate(name: name, hourly: hourly).filter {
            if case .name = $0 { return true } else { return false }
        }
        guard problems.isEmpty else { message = problems.map(\.text).joined(separator: "\n"); return }
        let saved = BasalProfile(name: name.trimmingCharacters(in: .whitespaces), hourlyRates: hourly)
        profiles.value.append(saved)
        activeID.value = saved.id // saved from the active schedule, so it is the active profile
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

/// Edits `ui.editing` (the draft lives there, not in this view, so a redraw or re-creation keeps typed values).
struct BasalProfileEditorView: View {
    @ObservedObject var ui: BasalProfilesUIState
    let onSave: (BasalProfile) -> Void

    private var original: BasalProfile? { ui.editing?.original }
    private var name: String { ui.editing?.name ?? "" }
    private var texts: [String] { ui.editing?.texts ?? [] }

    private var nameBinding: Binding<String> {
        Binding(get: { ui.editing?.name ?? "" }, set: { ui.editing?.name = $0 })
    }

    private func textBinding(_ hour: Int) -> Binding<String> {
        Binding(
            get: { ui.editing.map { hour < $0.texts.count ? $0.texts[hour] : "" } ?? "" },
            set: { value in if let count = ui.editing?.texts.count, hour < count { ui.editing?.texts[hour] = value } }
        )
    }

    private var hourly: [Decimal] {
        texts.map { Decimal(string: $0.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
    }

    private var problems: [BasalProfileMath.Problem] { BasalProfileMath.validate(name: name, hourly: hourly) }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Pavadinimas")) { TextField("Pavadinimas", text: nameBinding) }
                Section(header: Text("Paros suma: \(BasalProfileFormat.rate(BasalProfileMath.dailyTotal(hourly))) U/d")) {
                    ForEach(0 ..< BasalProfileMath.hours, id: \.self) { hour in
                        HStack {
                            Text(String(format: "%02d:00", hour)).monospacedDigit()
                            Spacer()
                            TextField("U/h", text: textBinding(hour))
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
            .navigationTitle((original?.name ?? "").isEmpty ? "Naujas profilis" : "Redaguoti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Atšaukti") { ui.editing = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Išsaugoti") {
                        guard var saved = original else { return }
                        saved.name = name.trimmingCharacters(in: .whitespaces)
                        saved.hourlyRates = hourly
                        onSave(saved)
                        ui.editing = nil
                    }
                    .disabled(original == nil || !problems.isEmpty)
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
    /// The active schedule re-read at the "Aktyvuoti" tap; the expected hash and "Ankstesnis" come from it.
    @State private var confirmSnapshot: ActiveBasalSnapshot?
    @State private var isSending = false
    @State private var result: String?
    @State private var lastSent: (profile: BasalProfile, hash: String)?

    /// "Dabar" = the schedule as it was when this screen was opened, with that moment. Taken once by the list and
    /// passed in, so no redraw recomputes it; comparison, warnings and the expected hash all use this one snapshot.
    let active: ActiveBasalSnapshot
    let capturedAt: Date

    var body: some View {
        Form {
            let current = active.hourly
            let oldTotal = current.map(BasalProfileMath.dailyTotal)
            let newTotal = BasalProfileMath.dailyTotal(profile.hourlyRates)
            Section(header: Text("Paros suma")) {
                Text(summary(old: oldTotal, new: newTotal))
                if active.isStale(now: capturedAt.timeIntervalSince1970) {
                    Text("⚠️ Nightscout profilio duomenys \(active.ageText(now: capturedAt.timeIntervalSince1970)) — aktyvus grafikas gali būti kitas.")
                        .foregroundColor(.orange)
                }
            }
            Section(header: Text("Valanda | dabar (\(BasalProfileFormat.clock(capturedAt))) | naujas | Δ")) {
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
                Button("Aktyvuoti") { prepareConfirmation(new: newTotal) }
                    .disabled(isSending || !problems.isEmpty || active.hash == nil)
                if lastSent != nil {
                    Button("Kartoti (siųsti tą patį)") { if let last = lastSent { send(last.profile, hash: last.hash) } }
                        .disabled(isSending)
                }
                if let result { Text(result).foregroundColor(.secondary) }
            }
            if isSending { ProgressView("Siunčiama…") }
            Section(header: Text("Diagnostika (hash)")) {
                HStack {
                    Text("Nightscout (\(BasalProfileFormat.clock(capturedAt)))")
                    Spacer()
                    Text(active.hash ?? "—").font(.caption.monospaced()).foregroundColor(.secondary)
                }
                HStack {
                    Text("Šis profilis")
                    Spacer()
                    Text(BasalProfileMath.hash(ofHourly: profile.hourlyRates)).font(.caption.monospaced()).foregroundColor(.secondary)
                }
                if let frozenHash {
                    HStack {
                        Text("Siunčiamas laukiamas")
                        Spacer()
                        Text(frozenHash).font(.caption.monospaced()).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
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

    /// The active schedule is read once more here, at the tap (the screen may have been open for minutes). Text,
    /// expected hash and the schedule saved as "Ankstesnis" are fixed from that read and not recomputed while shown.
    private func prepareConfirmation(new: Decimal) {
        let current = ActiveBasalSnapshot.current()
        let old = current.total
        var text = "\(profile.name)\n\(summary(old: old, new: new))\nTrio įrašys grafiką į pompą (tik Dana)."
        if current.hash != active.hash {
            text += "\n\n⚠️ Aktyvus grafikas pasikeitė nuo \(BasalProfileFormat.clock(capturedAt)) — lentelė ekrane pasenusi."
        }
        if let old, let pct = BasalProfileMath.percentChange(from: old, to: new), abs(pct) > 20 {
            text += "\n\n⚠️ Paros suma keičiasi daugiau nei 20 % (\(pct > 0 ? "+" : "")\(pct) %)."
        }
        if current.isStale() {
            text += "\n\n⚠️ Nightscout duomenys \(current.ageText()): Trio gali atmesti komandą, jei aktyvus grafikas pasikeitė."
        }
        if current.hourly == nil {
            text += "\n\nDabartinio grafiko negalima automatiškai išsaugoti kaip „Ankstesnis“ (ne sveikos valandos)."
        }
        confirmText = text
        frozenHash = current.hash
        confirmSnapshot = current
        showConfirm = true
    }

    private func activate(hash: String) {
        saveCurrentAsPrevious()
        send(profile, hash: hash)
    }

    /// Before every activation the schedule being replaced is kept as "Ankstesnis (YYYY-MM-DD HH:MM)", unless a
    /// saved profile with the same 24 rates already exists.
    private func saveCurrentAsPrevious() {
        guard let replaced = confirmSnapshot, let hourly = replaced.hourly,
              !profiles.value.contains(where: { BasalProfileMath.hash(ofHourly: $0.hourlyRates) == replaced.hash })
        else { return }
        profiles.value.append(BasalProfile(name: "Ankstesnis (\(BasalProfileFormat.stamp(Date())))", hourlyRates: hourly))
    }

    private func send(_ profile: BasalProfile, hash: String) {
        isSending = true
        lastSent = (profile, hash)
        pushNotificationManager.sendBasalSchedulePushNotification(profile: profile, expectedActiveHash: hash) { success, error in
            DispatchQueue.main.async {
                isSending = false
                // Marked active once the command is sent (LoopFollow does not read Trio's reply). If Trio refuses it,
                // the hash no longer matches Nightscout and the ✓ goes away on its own.
                let activeID = Storage.shared.activeBasalProfileID
                activeID.value = BasalActiveMarker.afterActivation(sent: profile.id, success: success, current: activeID.value)
                result = success
                    ? RemoteCommandMessage.sent + " Jei Trio praneš pompos klaidą, spauskite „Kartoti“ — tas pats siuntimas saugus."
                    : "Klaida: \(error ?? "nežinoma")"
                LogManager.shared.log(category: .apns, message: "sendBasalSchedulePushNotification \(success ? "succeeded" : "failed") for \(profile.name)")
            }
        }
    }
}
