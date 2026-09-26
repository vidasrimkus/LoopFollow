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

    enum AlertType {
        case confirmChange
        case statusSuccess
        case statusFailure
    }

    private var now: TimeInterval { Date().timeIntervalSince1970 }

    /// nil when there is no Trio reading, it is over 15 min old, or the mode is unknown to this build —
    /// then no row is disabled and every mode can be sent.
    private var currentMode: TrioDosingMode? {
        TrioDosingMode.current(dosingMode.value, now: now)
    }

    private var currentModeName: String {
        if let mode = currentMode { return mode.displayName }
        guard let reading = dosingMode.value else { return "—" }
        if TrioDosingMode.isStale(reading, now: now) { return "Unknown" }
        return reading.raw
    }

    var body: some View {
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
                                // The current mode is shown but cannot be sent again.
                                .disabled(mode == currentMode || isLoading)
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
                        message: Text(confirmationText),
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
        let minutes = TrioDosingMode.ageMinutes(dosingMode.value, now: now) ?? 0
        return "\(Localizer.formatTimestampToLocalString(at)) (\(minutes) min ago)"
    }

    /// Asked before every send. Switching to Closed Loop gets an extra warning because Trio then doses
    /// on its own again.
    private var confirmationText: String {
        guard let mode = selectedMode else { return "" }
        var text = "Perjungti \(currentModeName) → \(mode.displayName)?"
        if currentMode == nil {
            if let age = TrioDosingMode.ageMinutes(dosingMode.value, now: now) {
                text += "

Dabartinis režimas nežinomas (paskutiniai duomenys prieš \(age) min)"
            } else {
                text += "

Dabartinis režimas nežinomas (duomenų nėra)"
            }
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
