// LoopFollow
// TrioRemoteControlView.swift

import SwiftUI

struct TrioRemoteControlView: View {
    @ObservedObject var viewModel: TrioRemoteControlViewModel
    @ObservedObject private var activeOverrideNote = Observable.shared.override
    @ObservedObject private var activeTempTarget = Observable.shared.tempTarget
    @ObservedObject private var dosingMode = Observable.shared.dosingMode
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack {
                let columns = [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                ]

                LazyVGrid(columns: columns, spacing: 16) {
                    CommandButtonView(command: "Meal", iconName: "fork.knife", destination: MealView())
                    CommandButtonView(command: "Bolus", iconName: "syringe", destination: BolusView())
                    CommandButtonView(command: "Temp Target", iconName: "scope", destination: TempTargetView(), isActive: activeTempTarget.value != nil)
                    CommandButtonView(command: "Overrides", iconName: "slider.horizontal.3", destination: OverrideView(), isActive: activeOverrideNote.value != nil)
                    CommandButtonView(command: "Dosing Mode", iconName: "dial.medium", destination: DosingModeView(), isActive: isNonClosedMode)
                    CommandButtonView(command: "Basal Profiles", iconName: "chart.bar.xaxis", destination: BasalProfilesView())
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarTitle("Trio Remote Control", displayMode: .inline)
        }
    }

    /// Glow on the Dosing Mode button while Trio is known (fresh data) to be in a mode other than Closed Loop.
    private var isNonClosedMode: Bool {
        guard let mode = TrioDosingMode.current(dosingMode.value, now: Date().timeIntervalSince1970) else { return false }
        return mode != .closed
    }
}

struct CommandButtonView<Destination: View>: View {
    let command: String
    let iconName: String
    let destination: Destination
    /// Lights the button up with a glow while the corresponding override /
    /// temp target is active.
    var isActive: Bool = false

    var body: some View {
        NavigationLink(destination: destination) {
            VStack {
                Image(systemName: iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                Text(command)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green, lineWidth: 2.5)
                }
            }
            .shadow(color: isActive ? Color.green.opacity(0.7) : .clear, radius: isActive ? 9 : 0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
