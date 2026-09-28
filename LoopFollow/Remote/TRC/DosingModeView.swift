// LoopFollow
// DosingModeView.swift

import SwiftUI

struct DosingModeView: View {
    @Environment(\.presentationMode) private var presentationMode
    private let pushNotificationManager = PushNotificationManager()

    @ObservedObject var device = Storage.shared.device
    @ObservedObject var dosingMode = Observable.shared.dosingMode

    @State private var showAlert: Bool = false
    @State private var alertType: AlertType? = nil
    @State private var isLoading: Bool = false
    @State private var statusMessage: String? = nil
    @State private var selectedMode: TrioDosingMode? = nil
    /// Confirmation text taken at the tap; the 30 s timeline and devicestatus updates do not rewrite an open dialog.
    @State private var confirmText: String = ""

    enum AlertType {
        case confirmChange
        case statusSuccess
        case statusFailure
    }

    private var now: TimeInterval { Date().timeIntervalSince1970 }

    /// nil unless the Trio reading is fresh and one of the four modes. Marks the ✓ row; every row stays
    /// sendable (the displayed mode can be out of date).
    private var currentMode: TrioDosingMode? {
        TrioDosingMode.current(dosingMode.value, now: now)
    }

    private var currentModeName: String {
        switch TrioDosingMode.status(dosingMode.value, now: now) {
        case .none: return "—"
        case let .current(mode): return mode.displayName
        case let .unrecognized(raw): return raw
        case .stale, .future: return "Unknown"
        }
    }

    var body: some View {
        // Re-evaluated every 30 s while on screen (TimelineView pauses off screen), so a mode that goes stale
        // with the screen left open turns to Unknown without a tap.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            content
        }
    }

    private var content: some View {
        NavigationView {
            VStack {
                if device.value != "Trio" {
                    ErrorMessageView(
                        message: "Remote commands are currently only available for Trio."
                    )
                } else {
                    Form {
                        Section(header: Text("Current Mode")) {
                            HStack {
                                Text("Mode")
                                Spacer()
                                Text(currentModeName)
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Last device status")
                                Spacer()
                                Text(lastUpdateText)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Section(header: Text("Set Mode")) {
                            ForEach(TrioDosingMode.allCases) { mode in
                                Button(action: {
                                    selectedMode = mode
                                    confirmText = confirmationText(for: mode)
                                    alertType = .confirmChange
                                    showAlert = true
                                }) {
                                    HStack {
                                        Text(mode.displayName)
                                        Spacer()
                                        if mode == currentMode {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.green)
                                        } else {
                                            Image(systemName: "arrow.right.circle")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                // Every mode can be sent, the ✓ one too: the displayed mode comes from
                                // Nightscout and can lag behind Trio. Only an in-flight send disables rows.
                                .disabled(!TrioDosingMode.isRowEnabled(isLoading: isLoading))
                            }
                        }
                    }

                    if isLoading {
                        ProgressView("Please wait...")
                            .padding()
                    }
                }
            }
            .navigationTitle("Dosing Mode")
            .navigationBarTitleDisplayMode(.inline)
            .alert(isPresented: $showAlert) {
                switch alertType {
                case .confirmChange:
                    return Alert(
                        title: Text("Dosing Mode"),
                        message: Text(confirmText),
                        primaryButton: .default(Text("Confirm"), action: {
                            if let mode = selectedMode {
                                sendDosingMode(mode)
                            }
                        }),
                        secondaryButton: .cancel()
                    )
                case .statusSuccess:
                    return Alert(
                        title: Text("Command Sent"),
                        message: Text(statusMessage ?? ""),
                        dismissButton: .default(Text("OK"), action: {
                            presentationMode.wrappedValue.dismiss()
                        })
                    )
                case .statusFailure:
                    return Alert(
                        title: Text("Error"),
                        message: Text(statusMessage ?? "An error occurred."),
                        dismissButton: .default(Text("OK"))
                    )
                case .none:
                    return Alert(title: Text("Unknown Alert"))
                }
            }
        }
    }

    private var lastUpdateText: String {
        guard let at = dosingMode.value?.at else { return "—" }
        let time = Localizer.formatTimestampToLocalString(at)
        if let minutes = TrioDosingMode.ageMinutes(dosingMode.value, now: now) {
            return "\(time) (\(minutes) min ago)"
        }
        // Ahead of this phone's clock: never shown as "0 min ago".
        if TrioDosingMode.status(dosingMode.value, now: now) == .future {
            return "\(time) (laikas ateityje)"
        }
        return "\(time) (just now)"
    }

    /// Asked before every send. Switching to Closed Loop gets an extra warning because Trio then doses
    /// on its own again.
    private func confirmationText(for mode: TrioDosingMode) -> String {
        var text = "Perjungti \(currentModeName) → \(mode.displayName)?"
        if let note = TrioDosingMode.confirmationNote(dosingMode.value, now: now) {
            text += "\n\n" + note
        }
        if let note = TrioDosingMode.sameModeNote(selected: mode, reading: dosingMode.value, now: now) {
            text += "\n\n" + note
        }
        if mode == .closed {
            text += "\n\nTrio vėl pats duos insulino (korekcijos, SMB)"
        }
        return text
    }

    // MARK: - Functions

    private func sendDosingMode(_ mode: TrioDosingMode) {
        isLoading = true

        pushNotificationManager.sendDosingModePushNotification(mode: mode) { success, errorMessage in
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    self.statusMessage = RemoteCommandMessage.sent
                    self.alertType = .statusSuccess
                    LogManager.shared.log(category: .apns, message: "sendDosingModePushNotification succeeded for mode: \(mode.rawValue)")
                } else {
                    self.statusMessage = errorMessage ?? "Failed to send dosing mode command."
                    self.alertType = .statusFailure
                    LogManager.shared.log(category: .apns, message: "sendDosingModePushNotification failed for mode: \(mode.rawValue). Error: \(errorMessage ?? "unknown error")")
                }
                self.showAlert = true
            }
        }
    }
}
