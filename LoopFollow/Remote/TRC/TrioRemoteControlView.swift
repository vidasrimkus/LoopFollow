// LoopFollow
// TrioRemoteControlView.swift

import SwiftUI

struct TrioRemoteControlView: View {
    @ObservedObject var viewModel: TrioRemoteControlViewModel
    @ObservedObject private var activeOverrideNote = Observable.shared.override
    @ObservedObject private var activeTempTarget = Observable.shared.tempTarget
    @ObservedObject private var dosingMode = Observable.shared.dosingMode
    @Environment(\.presentationMode) var presentationMode

    /// Which command screen is open. Kept in @State and bound to links placed outside the lazy grid: this view is
    /// redrawn on every devicestatus (dosingMode / override / temp target), and links living inside a LazyVGrid
    /// lost their pushed screen on such a redraw — closing an open editor or confirmation with it.
    @State private var selection: TRCScreen?

    enum TRCScreen: Hashable, CaseIterable {
        case meal, bolus, tempTarget, overrides, dosingMode, basalProfiles
    }

    var body: some View {
        NavigationView {
            VStack {
                let columns = [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                ]

                LazyVGrid(columns: columns, spacing: 16) {
                    tile("Meal", "fork.knife", .meal)
                    tile("Bolus", "syringe", .bolus)
                    tile("Temp Target", "scope", .tempTarget, isActive: activeTempTarget.value != nil)
                    tile("Overrides", "slider.horizontal.3", .overrides, isActive: activeOverrideNote.value != nil)
                    tile("Dosing Mode", "dial.medium", .dosingMode, isActive: isNonClosedMode)
                    tile("Basal Profiles", "chart.bar.xaxis", .basalProfiles)
                }
                .padding(.horizontal)

                Spacer()
            }
            .background(links)
            .navigationBarTitle("Trio Remote Control", displayMode: .inline)
        }
    }

    private func tile(_ command: String, _ icon: String, _ screen: TRCScreen, isActive: Bool = false) -> some View {
        Button { selection = screen } label: {
            CommandTile(command: command, iconName: icon, isActive: isActive)
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Hidden, non-lazy links driven by `selection`.
    private var links: some View {
        VStack {
            ForEach(TRCScreen.allCases, id: \.self) { screen in
                NavigationLink(
                    destination: destination(screen),
                    isActive: Binding(get: { selection == screen }, set: { if !$0, selection == screen { selection = nil } })
                ) { EmptyView() }
            }
        }
        .hidden()
    }

    @ViewBuilder
    private func destination(_ screen: TRCScreen) -> some View {
        switch screen {
        case .meal: MealView()
        case .bolus: BolusView()
        case .tempTarget: TempTargetView()
        case .overrides: OverrideView()
        case .dosingMode: DosingModeView()
        case .basalProfiles: BasalProfilesView()
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
            CommandTile(command: command, iconName: iconName, isActive: isActive)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// The look of a command button, shared by the navigation-link buttons and the selection-driven TRC buttons.
struct CommandTile: View {
    let command: String
    let iconName: String
    var isActive: Bool = false

    var body: some View {
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
}
