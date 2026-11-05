// LoopFollow
// TherapyProfilesView.swift

import Combine
import HealthKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Kind configuration

extension TherapyKind {
    var title: String { self == .carbRatio ? "CR Profiles" : "ISF Profiles" }
    var shortName: String { self == .carbRatio ? "CR" : "ISF" }
    var exportFilename: String { self == .carbRatio ? "cr-profiles" : "isf-profiles" }

    var profiles: StorageValue<[TherapyProfile]> {
        self == .carbRatio ? Storage.shared.carbRatioProfiles : Storage.shared.isfProfiles
    }

    var activeID: StorageValue<UUID?> {
        self == .carbRatio ? Storage.shared.activeCarbRatioProfileID : Storage.shared.activeISFProfileID
    }

    /// Starting schedule for "Naujas profilis" when Nightscout has none: 10 g/U or 180 mg/dL all day.
    var defaultEntries: [TherapyEntry] {
        [TherapyEntry(minutes: 0, value: self == .carbRatio ? 100 : 180)]
    }

    /// Lower value = more insulin, said in the words of each setting.
    var lowerMeans: String { self == .carbRatio ? "mažesnis CR" : "mažesnis ISF" }
    var higherMeans: String { self == .carbRatio ? "didesnis CR" : "didesnis ISF" }
}

/// The app's glucose unit for ISF (Settings → units).
enum TherapyDisplay {
    static var isMmol: Bool { Storage.shared.units.value != "mg/dL" }
}

// MARK: - Nightscout snapshot

/// Trio's active CR or ISF schedule as this phone last loaded it from Nightscout (store.default.carbratio / sens).
struct ActiveTherapySnapshot {
    let kind: TherapyKind
    let entries: [(seconds: Int, value: Double)]
    /// Units of the Nightscout profile (Trio uploads `sens` in mg/dL or mmol/L). Ignored for CR.
    let nsMgdl: Bool
    let loadedAt: TimeInterval?

    static let staleAfter: TimeInterval = 15 * 60

    static func current(_ kind: TherapyKind) -> ActiveTherapySnapshot {
        let manager = ProfileManager.shared
        let units = manager.units
        let entries: [(seconds: Int, value: Double)] = kind == .carbRatio
            ? manager.carbRatioSchedule.map { (seconds: $0.timeAsSeconds, value: $0.value) }
            : manager.isfSchedule.map { (seconds: $0.timeAsSeconds, value: $0.value.doubleValue(for: units)) }
        return ActiveTherapySnapshot(
            kind: kind, entries: entries, nsMgdl: units == .milligramsPerDeciliter,
            loadedAt: Observable.shared.nsProfileLoadedAt.value
        )
    }

    /// The same values `current` reads, straight from a Nightscout profile store (units as `ProfileManager` reads
    /// them: "mg/dl" → mg/dL, anything else → mmol/L).
    init(kind: TherapyKind, store: NSProfile.Store, loadedAt: TimeInterval?) {
        let source: [(Double, Double)] = kind == .carbRatio
            ? store.carbratio.map { ($0.timeAsSeconds, $0.value) }
            : store.sens.map { ($0.timeAsSeconds, $0.value) }
        self.init(
            kind: kind, entries: source.map { (seconds: Int($0.0), value: $0.1) },
            nsMgdl: store.units.lowercased() == "mg/dl", loadedAt: loadedAt
        )
    }

    init(kind: TherapyKind, entries: [(seconds: Int, value: Double)], nsMgdl: Bool, loadedAt: TimeInterval?) {
        self.kind = kind
        self.entries = entries
        self.nsMgdl = nsMgdl
        self.loadedAt = loadedAt
    }

    /// The 48 Nightscout-form integers `hash` is computed from.
    var slots: [Int]? { entries.isEmpty ? nil : TherapyProfileMath.nightscoutSlots(entries, kind: kind, nsMgdl: nsMgdl) }
    var hash: String? { TherapyProfileMath.nightscoutHash(entries, kind: kind, nsMgdl: nsMgdl) }
    /// As a profile (stored units), or nil when it cannot be represented.
    var storedEntries: [TherapyEntry]? { TherapyProfileMath.storedEntries(fromNightscout: entries, kind: kind, nsMgdl: nsMgdl) }
    /// Every Nightscout value is exact in its unit (whole tenths of g/U, whole mg/dL, whole tenths of mmol/L).
    var isExact: Bool { TherapyProfileMath.nightscoutIsExact(entries, kind: kind, nsMgdl: nsMgdl) }
    /// A saved copy may differ from Trio's own values: ISF uploaded in mmol/L (rebuilt as the smallest mg/dL of each
    /// 0.1 mmol/L group — what Trio's mmol/L editor stores), or Nightscout values not exact in their unit (rounded).
    var isReconstructed: Bool { (kind == .isf && !nsMgdl) || !isExact }
    /// Trio's glucose unit as its Nightscout profile shows it; nil while no profile is loaded.
    var trioMmol: Bool? { entries.isEmpty ? nil : !nsMgdl }

    /// Why a saved copy is not exactly Trio's schedule; shown with "Dabar Trio'je", "Išsaugoti…" and "Ankstesnis".
    var reconstructionNote: String? {
        var notes: [String] = []
        if !isExact {
            notes.append(kind == .carbRatio
                ? "Nightscout CR ne 0.1 g/U tikslumu — išsaugota suapvalinta."
                : "Nightscout ISF ne \(nsMgdl ? "sveikų mg/dL" : "0.1 mmol/L") tikslumu — išsaugota suapvalinta.")
        }
        if kind == .isf, !nsMgdl {
            notes.append("ISF atkurtas iš mmol/L (mažiausia grupės mg/dL, kaip Trio mmol/L redaktorius); Trio esamos mg/dL gali skirtis ±1.")
        }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    /// The 48 slots in the unit shown.
    func displaySlots(mmol: Bool) -> [Int]? {
        slots?.map { TherapyProfileMath.displayValue(nightscout: $0, kind: kind, nsMgdl: nsMgdl, mmol: mmol) }
    }

    func receivedText(now: TimeInterval = Date().timeIntervalSince1970) -> String {
        guard let loadedAt, !entries.isEmpty else { return "Unknown" }
        let text = "\(BasalProfileFormat.clock(Date(timeIntervalSince1970: loadedAt))) (\(ageText(now: now)))"
        return isStale(now: now) ? "Unknown — \(text)" : text
    }

    func isStale(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let loadedAt, !entries.isEmpty else { return true }
        return now - loadedAt > Self.staleAfter
    }

    func ageText(now: TimeInterval = Date().timeIntervalSince1970) -> String {
        guard let loadedAt else { return "duomenų nėra" }
        return "prieš \(max(0, Int((now - loadedAt) / 60))) min"
    }
}

// MARK: - Change summary (activation)

enum TherapyChange {
    /// Rows in Nightscout form: Trio's slots now against the profile's slots as Nightscout would show them (same units).
    /// Directions and the > 20 % warning are decided on these integers; the unit shown is applied only to the text.
    static func rows(profile: TherapyProfile, active: ActiveTherapySnapshot) -> [TherapyProfileMath.ComparisonRow] {
        let new = TherapyProfileMath.nightscoutFormSlots(profile.entries, kind: profile.kind, nsMgdl: active.nsMgdl)
        return TherapyProfileMath.comparisonRows(now: active.slots, new: new)
    }

    /// The profile as it may be sent: ISF snapped to Trio's mmol/L editor values when Trio runs in mmol/L (Trio refuses
    /// anything else), with a note per changed entry. Same Nightscout form, so the hash and ✓ are unchanged.
    static func sendable(_ profile: TherapyProfile, trioMmol: Bool) -> (profile: TherapyProfile, notes: [String]) {
        let snapped = TherapyProfileMath.snappedForTrio(profile.entries, kind: profile.kind, trioMmol: trioMmol)
        var result = profile
        result.entries = snapped.entries
        return (result, snapped.notes)
    }

    /// A Nightscout-form value as text in the unit shown.
    static func shown(_ value: Int, kind: TherapyKind, nsMgdl: Bool, mmol: Bool) -> String {
        TherapyProfileMath.displayText(
            TherapyProfileMath.displayValue(nightscout: value, kind: kind, nsMgdl: nsMgdl, mmol: mmol), kind: kind, mmol: mmol
        )
    }

    /// ISF with Trio in mmol/L: Nightscout shows the same 0.1 mmol/L, but the profile's mg/dL differ from the value
    /// Trio's mmol/L editor would hold for some slot — equal on screen, not necessarily in mg/dL.
    static func isApproximate(profile: TherapyProfile, active: ActiveTherapySnapshot) -> Bool {
        guard profile.kind == .isf, !active.nsMgdl, let now = active.slots, now.count == TherapyProfileMath.slotCount else { return false }
        return zip(TherapyProfileMath.slots(profile.entries), now).contains { mgdl, tenths in
            TherapyProfileMath.mgdl(fromMmolTenths: tenths) != mgdl
        }
    }

    /// "Daugiau insulino (mažesnis CR): 06:00, 11:00" / "Mažiau insulino (…)" — lower CR or ISF means MORE insulin.
    /// With no change, "Reikšmės nesikeičia." — or, when `approximate`, "≈ (±1 mg/dL)".
    static func directionLines(_ rows: [TherapyProfileMath.ComparisonRow], kind: TherapyKind, approximate: Bool = false) -> [String] {
        func times(_ direction: TherapyProfileMath.InsulinDirection) -> [String] {
            rows.filter { row in row.now.map { TherapyProfileMath.direction(now: $0, new: row.new) == direction } ?? false }
                .map { TherapyProfileMath.clock($0.minutes) }
        }
        func list(_ t: [String]) -> String { t.count > 8 ? t.prefix(8).joined(separator: ", ") + " …" : t.joined(separator: ", ") }
        var lines: [String] = []
        let more = times(.more)
        let less = times(.less)
        if !more.isEmpty { lines.append("⬆︎ Daugiau insulino (\(kind.lowerMeans)): \(list(more))") }
        if !less.isEmpty { lines.append("⬇︎ Mažiau insulino (\(kind.higherMeans)): \(list(less))") }
        if more.isEmpty, less.isEmpty, rows.contains(where: { $0.now != nil }) {
            lines.append(approximate
                ? "≈ (±1 mg/dL) — Nightscout rodo tas pačias mmol/L reikšmes, mg/dL gali skirtis."
                : "Reikšmės nesikeičia.")
        }
        return lines
    }

    /// The schedule as the confirmation lists it: "HH:MM  value" (Trio phone time; ISF in mmol/L with its mg/dL),
    /// headed by the time-zone note.
    static func scheduleLines(_ profile: TherapyProfile, mmol: Bool) -> [String] {
        ["Laikai — Trio telefono laikas:"] + TherapyProfileMath.merged(profile.entries).map {
            "\(TherapyProfileMath.clock($0.minutes))  \(TherapyProfileMath.fullText($0.value, kind: profile.kind, mmol: mmol))"
        }
    }

    /// Extra warning when any slot changes by more than 20 % (decided in integers on Nightscout-form rows).
    static func bigChangeWarning(_ rows: [TherapyProfileMath.ComparisonRow], kind: TherapyKind) -> String? {
        guard let big = TherapyProfileMath.largestChange(rows), let now = big.now else { return nil }
        return "⚠️ \(kind.shortName) keičiasi daugiau nei 20 %: \(TherapyProfileMath.clock(big.minutes)) "
            + "\(TherapyProfileMath.percentText(now: now, new: big.new)) % (\(TherapyProfileMath.direction(now: now, new: big.new).text))."
    }

    /// Δ in the unit shown, with the rounded percent from the Nightscout-form integers. "≈" when the change is
    /// smaller than one step of the unit shown (e.g. ISF 100 → 101 mg/dL shown in mmol/L: both 5.6).
    static func deltaText(_ row: TherapyProfileMath.ComparisonRow, kind: TherapyKind, nsMgdl: Bool, mmol: Bool) -> String {
        guard let now = row.now else { return "" }
        guard now != row.new else { return "0" }
        let display = { TherapyProfileMath.displayValue(nightscout: $0, kind: kind, nsMgdl: nsMgdl, mmol: mmol) }
        let d = display(row.new) - display(now)
        let pct = TherapyProfileMath.percentChange(now: now, new: row.new).map { " (\($0 > 0 ? "+" : "")\($0) %)" } ?? ""
        guard d != 0 else { return "≈" + pct }
        return (d > 0 ? "+" : "-") + TherapyProfileMath.displayText(abs(d), kind: kind, mmol: mmol) + pct
    }
}

// MARK: - Export / import

struct TherapyProfilesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var profiles: [TherapyProfile]

    init(profiles: [TherapyProfile]) { self.profiles = profiles }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        profiles = try BasalProfilesDocument.decoder.decode([TherapyProfile].self, from: data)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(regularFileWithContents: BasalProfilesDocument.encoder.encode(profiles))
    }
}

// MARK: - Shared UI state

struct TherapyActivationRequest: Identifiable {
    let id: UUID
    let snapshot: ActiveTherapySnapshot
    let capturedAt: Date
    /// App unit at the tap (ISF): the screen does not switch units while open.
    let mmol: Bool
}

struct CurrentTherapyRequest: Identifiable {
    let id = UUID()
    let snapshot: ActiveTherapySnapshot
    let capturedAt: Date
    let mmol: Bool
}

/// One editor row: start time and the typed value. An unchanged text keeps the stored value as it was (an ISF profile
/// edited in mmol/L does not move 46 → 47 mg/dL just by being opened and saved).
struct TherapyDraftRow: Identifiable, Equatable {
    let id: UUID
    var minutes: Int
    var text: String
    let originalText: String?
    let originalValue: Int?

    init(id: UUID = UUID(), minutes: Int, text: String, originalText: String? = nil, originalValue: Int? = nil) {
        self.id = id
        self.minutes = minutes
        self.text = text
        self.originalText = originalText
        self.originalValue = originalValue
    }
}

/// The editor's unsaved values. Nothing is written to Storage until "Išsaugoti".
struct TherapyProfileDraft: Identifiable {
    let original: TherapyProfile
    /// App unit when the editor was opened.
    let mmol: Bool
    /// Trio runs in mmol/L (its Nightscout profile, read when the editor was opened): ISF values are snapped to what
    /// Trio's mmol/L editor stores, because Trio refuses anything else.
    let trioMmol: Bool
    var name: String
    var rows: [TherapyDraftRow]

    var id: UUID { original.id }
    var kind: TherapyKind { original.kind }

    init(_ profile: TherapyProfile, mmol: Bool, trioMmol: Bool = false) {
        original = profile
        self.mmol = mmol
        self.trioMmol = trioMmol
        name = profile.name
        var rows = TherapyProfileMath.merged(profile.entries).map { entry -> TherapyDraftRow in
            let text = TherapyProfileMath.editText(entry.value, kind: profile.kind, mmol: mmol)
            return TherapyDraftRow(minutes: entry.minutes, text: text, originalText: text, originalValue: entry.value)
        }
        if rows.first?.minutes != 0 {
            // First row is always 00:00; a schedule without it takes the last value (daily wrap).
            let value = rows.last?.originalValue ?? profile.kind.defaultEntries[0].value
            let text = TherapyProfileMath.editText(value, kind: profile.kind, mmol: mmol)
            rows.insert(TherapyDraftRow(minutes: 0, text: text, originalText: text, originalValue: value), at: 0)
        }
        self.rows = rows
    }

    /// Rows sorted by start, each value in the stored unit (snapped for Trio in mmol/L, with a note per change);
    /// problems include unparsable values and validation.
    func parsed() -> (entries: [TherapyEntry], problems: [TherapyProfileMath.Problem], notes: [String]) {
        let raw = rawParsed()
        let snapped = TherapyProfileMath.snappedForTrio(raw.entries, kind: kind, trioMmol: trioMmol)
        return (snapped.entries, raw.problems, snapped.notes)
    }

    /// The stored value a row stands for before snapping: unchanged text keeps its stored value, else the parsed text.
    func value(of row: TherapyDraftRow) -> Int? {
        if let originalValue = row.originalValue, row.text == row.originalText { return originalValue }
        return try? TherapyProfileMath.parse(row.text, kind: kind, mmol: mmol).get()
    }

    private func rawParsed() -> (entries: [TherapyEntry], problems: [TherapyProfileMath.Problem]) {
        var entries: [TherapyEntry] = []
        var parseProblems: [TherapyProfileMath.Problem] = []
        for row in rows.sorted(by: { $0.minutes < $1.minutes }) {
            if let originalValue = row.originalValue, row.text == row.originalText {
                entries.append(TherapyEntry(minutes: row.minutes, value: originalValue))
                continue
            }
            switch TherapyProfileMath.parse(row.text, kind: kind, mmol: mmol) {
            case let .success(value): entries.append(TherapyEntry(minutes: row.minutes, value: value))
            case let .failure(error): parseProblems.append(.entry(row.minutes, error.text))
            }
        }
        let problems = TherapyProfileMath.validate(name: name, kind: kind, entries: entries)
        return (entries, parseProblems + problems)
    }

    /// A start for a new row: the first free half-hour after the last row, else any free one.
    func nextFreeMinutes() -> Int? {
        let used = Set(rows.map(\.minutes))
        let last = rows.map(\.minutes).max() ?? 0
        let after = stride(from: last + 30, to: 24 * 60, by: 30).first { !used.contains($0) }
        return after ?? stride(from: 30, to: 24 * 60, by: 30).first { !used.contains($0) }
    }
}

/// Which sheet of a CR/ISF screen is open, and the editor draft — kept outside the views (like
/// `BasalProfilesUIState`), so a devicestatus-driven redraw or re-creation of the list keeps them open.
final class TherapyProfilesUIState: ObservableObject {
    static let carbRatio = TherapyProfilesUIState()
    static let isf = TherapyProfilesUIState()

    static func shared(_ kind: TherapyKind) -> TherapyProfilesUIState {
        kind == .carbRatio ? carbRatio : isf
    }

    @Published var activation: TherapyActivationRequest?
    @Published var editing: TherapyProfileDraft?
    @Published var currentView: CurrentTherapyRequest?
}

// MARK: - "Dabar Trio'je" table

struct CurrentTherapyView: View {
    let snapshot: ActiveTherapySnapshot
    let capturedAt: Date
    let mmol: Bool
    let matchName: String?

    var body: some View {
        Form {
            if let slots = snapshot.displaySlots(mmol: mmol) {
                Section {
                    HStack {
                        Text("Gauta iš NS")
                        Spacer()
                        Text(snapshot.receivedText(now: capturedAt.timeIntervalSince1970))
                            .foregroundColor(snapshot.isStale(now: capturedAt.timeIntervalSince1970) ? .orange : .secondary)
                    }
                    if snapshot.kind == .isf {
                        HStack { Text("Nightscout vienetai"); Spacer(); Text(snapshot.nsMgdl ? "mg/dL" : "mmol/L").foregroundColor(.secondary) }
                    }
                    if let matchName {
                        HStack { Text("Profilis"); Spacer(); Text(matchName).foregroundColor(.secondary) }
                    } else {
                        Text("Neatitinka nė vieno išsaugoto profilio.").foregroundColor(.orange)
                    }
                }
                Section(header: Text("Laikas (Trio telefono laikas) | \(TherapyProfileMath.unit(snapshot.kind, mmol: mmol))")) {
                    ForEach(Array(TherapyProfileMath.slotSegments(slots).enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(TherapyProfileMath.clock(row.minutes))
                            Spacer()
                            Text(TherapyProfileMath.displayText(row.value, kind: snapshot.kind, mmol: mmol))
                        }
                        .monospacedDigit()
                    }
                }
            } else {
                Text("Nightscout profilio dar nėra.").foregroundColor(.secondary)
            }
        }
        .navigationTitle("Dabar Trio'je")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - List

struct TherapyProfilesView: View {
    let kind: TherapyKind

    @ObservedObject private var profiles: StorageValue<[TherapyProfile]>
    @ObservedObject private var activeID: StorageValue<UUID?>
    @ObservedObject private var ui: TherapyProfilesUIState
    @ObservedObject private var device = Storage.shared.device
    @ObservedObject private var units = Storage.shared.units

    @State private var showSaveCurrent = false
    @State private var newName = ""
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var message: String?

    /// Nightscout's active schedule, taken on appear, on "Atnaujinti" and when a profile load finishes — not observed
    /// live, so a devicestatus update never redraws this screen under an open sheet.
    @State private var active: ActiveTherapySnapshot

    init(kind: TherapyKind) {
        self.kind = kind
        _profiles = ObservedObject(wrappedValue: kind.profiles)
        _activeID = ObservedObject(wrappedValue: kind.activeID)
        _ui = ObservedObject(wrappedValue: TherapyProfilesUIState.shared(kind))
        _active = State(initialValue: ActiveTherapySnapshot.current(kind))
    }

    private var mmol: Bool { units.value != "mg/dL" }
    private var unit: String { TherapyProfileMath.unit(kind, mmol: mmol) }

    var body: some View {
        Form {
            if device.value != "Trio" {
                Text("Remote commands are currently only available for Trio.").foregroundColor(.secondary)
            }
            currentSection
            profilesSection
            Section {
                Button("Naujas profilis") {
                    ui.editing = draft(TherapyProfile(kind: kind, name: "", entries: active.storedEntries ?? kind.defaultEntries))
                }
                Button("Eksportuoti (JSON)") { showExporter = true }.disabled(profiles.value.isEmpty)
                Button("Importuoti (JSON)") { showImporter = true }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            TaskScheduler.shared.rescheduleTask(id: .profile, to: Date())
            active = ActiveTherapySnapshot.current(kind)
            let initial = TherapyActiveMarker.initialActiveID(profiles.value, storedID: activeID.value, nsHash: active.hash, nsMgdl: active.nsMgdl)
            if initial != activeID.value { activeID.value = initial }
        }
        .onReceive(Observable.shared.nsProfileLoadedAt.$value.dropFirst().receive(on: DispatchQueue.main)) { _ in
            active = ActiveTherapySnapshot.current(kind)
        }
        .sheet(item: $ui.editing) { _ in
            TherapyProfileEditorView(ui: ui) { saved in profiles.value = TherapyProfileList.upsert(saved, into: profiles.value) }
                .interactiveDismissDisabled()
        }
        .sheet(item: $ui.currentView) { request in
            NavigationStack {
                CurrentTherapyView(
                    snapshot: request.snapshot, capturedAt: request.capturedAt, mmol: request.mmol,
                    matchName: TherapyActiveMarker.matchingProfile(
                        profiles.value, activeID: activeID.value, nsHash: request.snapshot.hash, nsMgdl: request.snapshot.nsMgdl
                    )?.name
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Uždaryti") { ui.currentView = nil } }
                }
            }
        }
        .sheet(item: $ui.activation) { request in
            NavigationStack {
                Group {
                    if let profile = TherapyProfileList.profile(id: request.id, in: profiles.value) {
                        TherapyProfileActivationView(
                            profile: profile, profiles: profiles, active: request.snapshot,
                            capturedAt: request.capturedAt, mmol: request.mmol
                        )
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
            document: TherapyProfilesDocument(profiles: profiles.value),
            contentType: .json,
            defaultFilename: kind.exportFilename
        ) { result in
            if case let .failure(error) = result { message = "Eksportas nepavyko: \(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in importProfiles(result) }
    }

    private var currentSection: some View {
        Section(header: Text("Dabar Trio'je"), footer: Text("Laikai — Trio telefono laikas, ne šio telefono.")) {
            if let slots = active.displaySlots(mmol: mmol) {
                Button {
                    ui.currentView = CurrentTherapyRequest(snapshot: active, capturedAt: Date(), mmol: mmol)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(TherapyProfileMath.slotSegments(slots).enumerated()), id: \.offset) { _, segment in
                            HStack {
                                Text(TherapyProfileMath.clock(segment.minutes)).monospacedDigit()
                                Spacer()
                                Text("\(TherapyProfileMath.displayText(segment.value, kind: kind, mmol: mmol)) \(unit)").monospacedDigit()
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if kind == .isf, active.nsMgdl == mmol {
                    Text("Nightscout ISF rodo \(active.nsMgdl ? "mg/dL" : "mmol/L"); čia perskaičiuota į \(unit).")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let match = TherapyActiveMarker.matchingProfile(profiles.value, activeID: activeID.value, nsHash: active.hash, nsMgdl: active.nsMgdl) {
                    HStack { Text("Profilis"); Spacer(); Text(match.name).foregroundColor(.secondary) }
                } else {
                    Text("Neatitinka nė vieno išsaugoto profilio.").foregroundColor(.orange)
                }
                if active.storedEntries == nil {
                    Text("Grafike yra laikų ne pusvalandžio tinklelyje arba reikšmių už ribų — jo negalima išsaugoti kaip profilio.")
                        .foregroundColor(.orange)
                } else if let note = active.reconstructionNote {
                    Text(note).font(.caption).foregroundColor(.orange)
                }
            } else {
                Text("Nightscout profilio dar nėra.").foregroundColor(.secondary)
            }
            HStack {
                Text("Gauta iš NS")
                Spacer()
                Text(active.receivedText()).foregroundColor(active.isStale() ? .orange : .secondary)
            }
            Button("Atnaujinti") {
                TaskScheduler.shared.rescheduleTask(id: .profile, to: Date())
                active = ActiveTherapySnapshot.current(kind)
            }
            Button("Išsaugoti kaip profilį…") {
                newName = ""
                showSaveCurrent = true
            }
            .disabled(active.storedEntries == nil)
        }
    }

    private var profilesSection: some View {
        Section(header: Text("Profiliai")) {
            if profiles.value.isEmpty {
                Text("Išsaugotų profilių nėra.").foregroundColor(.secondary)
            }
            ForEach(profiles.value) { profile in
                let state = TherapyActiveMarker.rowState(profile, activeID: activeID.value, nsHash: active.hash, nsMgdl: active.nsMgdl)
                HStack {
                    Button { ui.editing = draft(profile) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(profile.name).font(.headline)
                                Text(rangeText(profile)).font(.subheadline).foregroundColor(.secondary)
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
                        ui.activation = TherapyActivationRequest(
                            id: profile.id, snapshot: ActiveTherapySnapshot.current(kind), capturedAt: Date(), mmol: mmol
                        )
                    }
                    .buttonStyle(.bordered)

                    Menu {
                        Button("Kopijuoti") { copy(profile) }
                        Button("Trinti", role: .destructive) { delete(profile) }
                            .disabled(!TherapyActiveMarker.canDelete(profile, activeID: activeID.value))
                    } label: {
                        Image(systemName: "ellipsis.circle").imageScale(.large)
                    }
                    .buttonStyle(.borderless)
                }
                .swipeActions {
                    Button("Redaguoti") { ui.editing = draft(profile) }.tint(.blue)
                    Button("Kopijuoti") { copy(profile) }.tint(.gray)
                    if TherapyActiveMarker.canDelete(profile, activeID: activeID.value) {
                        Button("Trinti", role: .destructive) { delete(profile) }
                    }
                }
            }
        }
    }

    /// "3 laikai · 8.5–12.0 g/U".
    private func rangeText(_ profile: TherapyProfile) -> String {
        let shown = TherapyProfileMath.merged(profile.entries).map { TherapyProfileMath.displayValue($0.value, kind: kind, mmol: mmol) }
        guard let low = shown.min(), let high = shown.max() else { return "" }
        let values = low == high
            ? TherapyProfileMath.displayText(low, kind: kind, mmol: mmol)
            : "\(TherapyProfileMath.displayText(low, kind: kind, mmol: mmol))–\(TherapyProfileMath.displayText(high, kind: kind, mmol: mmol))"
        return "\(shown.count) \(shown.count == 1 ? "laikas" : "laikai") · \(values) \(unit)"
    }

    // MARK: Actions

    /// Editor draft in the app unit, snapping ISF for Trio in mmol/L (Trio's units read at the tap).
    private func draft(_ profile: TherapyProfile) -> TherapyProfileDraft {
        TherapyProfileDraft(profile, mmol: mmol, trioMmol: ActiveTherapySnapshot.current(kind).trioMmol ?? false)
    }

    private func copy(_ profile: TherapyProfile) {
        let name = String("\(profile.name) (kopija)".prefix(TherapyProfileMath.maxNameLength))
        profiles.value.append(TherapyProfile(kind: kind, name: name, entries: profile.entries))
    }

    private func delete(_ profile: TherapyProfile) {
        guard TherapyActiveMarker.canDelete(profile, activeID: activeID.value) else { return }
        profiles.value.removeAll { $0.id == profile.id }
    }

    private func saveCurrent(named name: String) {
        guard let entries = active.storedEntries else { return }
        let problems = TherapyProfileMath.validate(name: name, kind: kind, entries: entries)
        guard problems.isEmpty else { message = problems.map(\.text).joined(separator: "\n"); return }
        let saved = TherapyProfile(kind: kind, name: name.trimmingCharacters(in: .whitespaces), entries: entries)
        profiles.value.append(saved)
        activeID.value = saved.id
        if let note = active.reconstructionNote {
            message = "Išsaugota. " + note
        }
    }

    private func importProfiles(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let imported = try BasalProfilesDocument.decoder.decode([TherapyProfile].self, from: Data(contentsOf: url))
                .filter { $0.kind == kind && !$0.entries.isEmpty }
            var list = profiles.value
            var added = 0
            for p in imported where !list.contains(where: { $0.id == p.id || ($0.name == p.name && $0.entries == p.entries) }) {
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

/// Edits `ui.editing` (the draft lives there, so a redraw or re-creation keeps typed values). A list of segments:
/// the first starts at 00:00 and cannot be moved or removed; other starts are picked in 30-minute steps.
struct TherapyProfileEditorView: View {
    @ObservedObject var ui: TherapyProfilesUIState
    let onSave: (TherapyProfile) -> Void

    private var draft: TherapyProfileDraft? { ui.editing }

    private var nameBinding: Binding<String> {
        Binding(get: { ui.editing?.name ?? "" }, set: { ui.editing?.name = $0 })
    }

    private func index(_ id: UUID) -> Int? { ui.editing?.rows.firstIndex { $0.id == id } }

    private func textBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { index(id).flatMap { ui.editing?.rows[$0].text } ?? "" },
            set: { value in if let i = index(id) { ui.editing?.rows[i].text = value } }
        )
    }

    private func minutesBinding(_ id: UUID) -> Binding<Int> {
        Binding(
            get: { index(id).flatMap { ui.editing?.rows[$0].minutes } ?? 30 },
            set: { value in
                guard let i = index(id) else { return }
                ui.editing?.rows[i].minutes = value
                ui.editing?.rows.sort { $0.minutes < $1.minutes }
            }
        )
    }

    var body: some View {
        NavigationView {
            if let draft {
                let kind = draft.kind
                let mmol = draft.mmol
                let unit = TherapyProfileMath.unit(kind, mmol: mmol)
                let result = draft.parsed()
                Form {
                    Section(header: Text("Pavadinimas")) { TextField("Pavadinimas", text: nameBinding) }
                    Section(
                        header: Text("Laikas (Trio telefono laikas) | \(unit)"),
                        footer: Text(editorFooter(kind: kind, mmol: mmol))
                    ) {
                        ForEach(draft.rows) { row in
                            HStack {
                                if row.minutes == 0, draft.rows.first?.id == row.id {
                                    Text("00:00").monospacedDigit()
                                } else {
                                    Picker("", selection: minutesBinding(row.id)) {
                                        ForEach(1 ..< TherapyProfileMath.slotCount, id: \.self) { slot in
                                            Text(TherapyProfileMath.clock(slot * 30)).tag(slot * 30)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                }
                                Spacer()
                                TextField(unit, text: textBinding(row.id))
                                    .keyboardType(kind == .isf && !mmol ? .numberPad : .decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 70)
                                Text(unit).foregroundColor(.secondary)
                                if kind == .isf, mmol || draft.trioMmol, let value = draft.value(of: row) {
                                    let sent = draft.trioMmol ? TherapyProfileMath.trioMmolEditorValue(mgdl: value) : value
                                    Text("\(sent) mg/dL")
                                        .font(.caption).foregroundColor(sent == value ? .secondary : .orange)
                                }
                                if draft.rows.first?.id != row.id {
                                    Button(role: .destructive) {
                                        ui.editing?.rows.removeAll { $0.id == row.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill").foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        Button("Pridėti laiką") { addRow() }
                            .disabled(draft.rows.count >= TherapyProfileMath.maxEntries || draft.nextFreeMinutes() == nil)
                    }
                    if !result.problems.isEmpty {
                        Section(header: Text("Klaidos")) {
                            ForEach(result.problems.map(\.text), id: \.self) { Text($0).foregroundColor(.red) }
                        }
                    }
                    if !result.notes.isEmpty {
                        Section(header: Text("Trio mmol/L")) {
                            ForEach(result.notes, id: \.self) { Text($0).foregroundColor(.orange) }
                        }
                    }
                }
                .navigationTitle(draft.original.name.isEmpty ? "Naujas \(kind.shortName) profilis" : "Redaguoti")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Atšaukti") { ui.editing = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Išsaugoti") {
                            var saved = draft.original
                            saved.name = draft.name.trimmingCharacters(in: .whitespaces)
                            saved.entries = result.entries
                            onSave(saved)
                            ui.editing = nil
                        }
                        .disabled(!result.problems.isEmpty)
                    }
                }
            }
        }
    }

    private func editorFooter(kind: TherapyKind, mmol: Bool) -> String {
        let range = kind == .carbRatio
            ? "1.0–50.0 g/U, žingsnis 0.1."
            : (mmol ? "0.5–30.0 mmol/L, žingsnis 0.1 (saugoma mg/dL)." : "9–540 mg/dL, žingsnis 1.")
        return "\(range) Mažesnis \(kind.shortName) = daugiau insulino.\nLaikai — Trio telefono laikas, ne šio telefono."
    }

    private func addRow() {
        guard let draft = ui.editing, let minutes = draft.nextFreeMinutes() else { return }
        let source = draft.rows.last { $0.minutes < minutes } ?? draft.rows.last
        // The copy keeps the source's stored value while its text is unchanged, so two rows reading "2.6" cannot
        // stand for different mg/dL.
        ui.editing?.rows.append(TherapyDraftRow(
            minutes: minutes, text: source?.text ?? "", originalText: source?.text, originalValue: source.flatMap { draft.value(of: $0) }
        ))
        ui.editing?.rows.sort { $0.minutes < $1.minutes }
    }
}

// MARK: - Activation

struct TherapyProfileActivationView: View {
    let profile: TherapyProfile
    @ObservedObject var profiles: StorageValue<[TherapyProfile]>
    /// The schedule as it was when this screen was opened, with that moment; taken by the list at the tap.
    let active: ActiveTherapySnapshot
    let capturedAt: Date
    let mmol: Bool

    private let pushNotificationManager = PushNotificationManager()

    @State private var showConfirm = false
    @State private var confirmText = ""
    @State private var frozenHash: String?
    /// The active schedule re-read at the "Aktyvuoti" tap; the expected hash and "Ankstesnis" come from it.
    @State private var confirmSnapshot: ActiveTherapySnapshot?
    @State private var isSending = false
    @State private var result: String?
    @State private var lastSent: (profile: TherapyProfile, hash: String)?
    /// The profile exactly as it will be sent (ISF snapped for Trio in mmol/L), fixed at the "Aktyvuoti" tap.
    @State private var frozenProfile: TherapyProfile?

    private var kind: TherapyKind { profile.kind }
    private var unit: String { TherapyProfileMath.unit(kind, mmol: mmol) }

    var body: some View {
        Form {
            let rows = TherapyChange.rows(profile: profile, active: active)
            let sendable = TherapyChange.sendable(profile, trioMmol: !active.nsMgdl)
            Section(header: Text("Pokytis")) {
                ForEach(
                    TherapyChange.directionLines(rows, kind: kind, approximate: TherapyChange.isApproximate(profile: profile, active: active)),
                    id: \.self
                ) { Text($0) }
                if let warning = TherapyChange.bigChangeWarning(rows, kind: kind) {
                    Text(warning).foregroundColor(.red)
                }
                Text("Mažesnis \(kind.shortName) = daugiau insulino; didesnis = mažiau.").font(.caption).foregroundColor(.secondary)
                if active.isStale(now: capturedAt.timeIntervalSince1970) {
                    Text("⚠️ Nightscout profilio duomenys \(active.ageText(now: capturedAt.timeIntervalSince1970)) — aktyvus grafikas gali būti kitas.")
                        .foregroundColor(.orange)
                }
            }
            Section(
                header: Text("Laikas (Trio telefono laikas) | dabar (nuskaityta \(BasalProfileFormat.clock(capturedAt))) | naujas | Δ, \(unit)"),
                footer: Text("Laikai — Trio telefono laikas, ne šio telefono.")
            ) {
                ForEach(rows, id: \.minutes) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(TherapyProfileMath.clock(row.minutes))
                        Spacer()
                        Text(row.now.map { TherapyChange.shown($0, kind: kind, nsMgdl: active.nsMgdl, mmol: mmol) } ?? "—")
                            .frame(width: 45, alignment: .trailing).foregroundColor(.secondary)
                        Text(TherapyChange.shown(row.new, kind: kind, nsMgdl: active.nsMgdl, mmol: mmol)).frame(width: 45, alignment: .trailing)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(TherapyChange.deltaText(row, kind: kind, nsMgdl: active.nsMgdl, mmol: mmol))
                            if let now = row.now, now != row.new {
                                Text(TherapyProfileMath.direction(now: now, new: row.new).text).font(.caption2)
                            }
                        }
                        .frame(width: 105, alignment: .trailing)
                        .foregroundColor(color(row))
                    }
                    .monospacedDigit()
                }
            }
            if kind == .isf, mmol || !active.nsMgdl {
                Section(header: Text("Bus išsaugota (mg/dL), Trio telefono laikas")) {
                    ForEach(sendable.notes, id: \.self) { Text($0).foregroundColor(.orange) }
                    ForEach(TherapyProfileMath.merged(sendable.profile.entries), id: \.minutes) { entry in
                        HStack {
                            Text(TherapyProfileMath.clock(entry.minutes))
                            Spacer()
                            Text(TherapyProfileMath.fullText(entry.value, kind: kind, mmol: true))
                        }
                        .monospacedDigit()
                    }
                }
            }
            let problems = TherapyProfileMath.validate(name: profile.name, kind: kind, entries: profile.entries)
            if !problems.isEmpty {
                Section(header: Text("Negalima siųsti")) {
                    ForEach(problems.map(\.text), id: \.self) { Text($0).foregroundColor(.red) }
                }
            }
            Section {
                Button("Aktyvuoti") { prepareConfirmation() }
                    .disabled(isSending || !problems.isEmpty || active.hash == nil)
                if lastSent != nil {
                    Button("Kartoti (siųsti tą patį)") { if let last = lastSent { send(last.profile, hash: last.hash) } }
                        .disabled(isSending)
                }
                if let result { Text(result).foregroundColor(.secondary) }
            }
            if isSending { ProgressView("Siunčiama…") }
            Section(header: Text("Diagnostika (hash)")) {
                hashRow("Nightscout (\(BasalProfileFormat.clock(capturedAt)))", active.hash ?? "—")
                hashRow("Šis profilis", TherapyProfileMath.nightscoutFormHash(profile.entries, kind: kind, nsMgdl: active.nsMgdl))
                if let frozenHash { hashRow("Siunčiamas laukiamas", frozenHash) }
            }
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Aktyvuoti \(kind.shortName) profilį", isPresented: $showConfirm) {
            Button("Aktyvuoti", role: .destructive) {
                if let hash = frozenHash, let toSend = frozenProfile { activate(toSend, hash: hash) }
            }
            Button("Atšaukti", role: .cancel) {}
        } message: {
            Text(confirmText)
        }
    }

    private func hashRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).font(.caption.monospaced()).foregroundColor(.secondary)
        }
    }

    private func color(_ row: TherapyProfileMath.ComparisonRow) -> Color {
        guard let now = row.now else { return .secondary }
        switch TherapyProfileMath.direction(now: now, new: row.new) {
        case .more: return .red
        case .less: return .blue
        case .same: return .secondary
        }
    }

    /// The active schedule is read once more here, at the tap. Text, expected hash and "Ankstesnis" are fixed from
    /// that read and not recomputed while shown.
    private func prepareConfirmation() {
        let current = ActiveTherapySnapshot.current(kind)
        let rows = TherapyChange.rows(profile: profile, active: current)
        let sendable = TherapyChange.sendable(profile, trioMmol: !current.nsMgdl)
        var text = profile.name + "\n" + TherapyChange.scheduleLines(sendable.profile, mmol: mmol).joined(separator: "\n")
        if !sendable.notes.isEmpty { text += "\n\n" + sendable.notes.joined(separator: "\n") }
        let lines = TherapyChange.directionLines(rows, kind: kind, approximate: TherapyChange.isApproximate(profile: profile, active: current))
        if !lines.isEmpty { text += "\n\n" + lines.joined(separator: "\n") }
        text += "\n\nTrio išsaugos naują \(kind.shortName) grafiką."
        if current.hash != active.hash {
            text += "\n\n⚠️ Aktyvus grafikas pasikeitė nuo \(BasalProfileFormat.clock(capturedAt)) — lentelė ekrane pasenusi."
        }
        if let warning = TherapyChange.bigChangeWarning(rows, kind: kind) {
            text += "\n\n" + warning
        }
        if current.isStale() {
            text += "\n\n⚠️ Nightscout duomenys \(current.ageText()): Trio gali atmesti komandą, jei aktyvus grafikas pasikeitė."
        }
        if current.storedEntries == nil {
            text += "\n\nDabartinio grafiko negalima automatiškai išsaugoti kaip „Ankstesnis“."
        } else if let note = current.reconstructionNote {
            text += "\n\n„Ankstesnis“: " + note
        }
        confirmText = text
        frozenProfile = sendable.profile
        frozenHash = current.hash
        confirmSnapshot = current
        showConfirm = true
    }

    private func activate(_ toSend: TherapyProfile, hash: String) {
        saveCurrentAsPrevious()
        send(toSend, hash: hash)
    }

    /// Before every activation the schedule being replaced is kept as "Ankstesnis (YYYY-MM-DD HH:MM)", unless a
    /// saved profile already has its hash. Not on "Kartoti" (same reasoning as basal).
    private func saveCurrentAsPrevious() {
        guard let replaced = confirmSnapshot, let entries = replaced.storedEntries, let replacedHash = replaced.hash,
              !profiles.value.contains(where: {
                  TherapyProfileMath.nightscoutFormHash($0.entries, kind: kind, nsMgdl: replaced.nsMgdl) == replacedHash
              })
        else { return }
        profiles.value.append(TherapyProfile(kind: kind, name: "Ankstesnis (\(BasalProfileFormat.stamp(Date())))", entries: entries))
    }

    private func send(_ profile: TherapyProfile, hash: String) {
        isSending = true
        lastSent = (profile, hash)
        pushNotificationManager.sendTherapySchedulePushNotification(profile: profile, expectedActiveHash: hash) { success, error in
            DispatchQueue.main.async {
                isSending = false
                let activeID = profile.kind.activeID
                activeID.value = TherapyActiveMarker.afterActivation(sent: profile.id, success: success, current: activeID.value)
                result = success
                    ? RemoteCommandMessage.sent + " Jei Trio praneš klaidą (pvz. ciklas vyksta), spauskite „Kartoti“ — tas pats siuntimas saugus."
                    : "Klaida: \(error ?? "nežinoma")"
                LogManager.shared.log(category: .apns, message: "sendTherapySchedulePushNotification \(success ? "succeeded" : "failed") for \(profile.kind.shortName) \(profile.name)")
            }
        }
    }
}
