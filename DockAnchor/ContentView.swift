//
//  ContentView.swift
//  DockAnchor
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var coordinator: DockCoordinator
    @EnvironmentObject var appSettings: AppSettings
    @State private var showingSettings = false
    @State private var showingNewProfile = false
    @State private var editingProfile: DockProfile?
    @State private var showingPermissionHelp = false

    var body: some View {
        VStack(spacing: 20) {
            headerView
            Divider()
            StatusSection(showingPermissionHelp: $showingPermissionHelp)
            ControlsSection(showingSettings: $showingSettings)
            Divider()
            AnchorDisplaySection()
            ProfilesSection(showingNewProfile: $showingNewProfile, editingProfile: $editingProfile)
            DockSettingsSection()
        }
        .padding()
        .frame(width: 420, height: 820)
        .background(.background)
        .sheet(isPresented: $showingSettings) {
            SettingsView().preferredColorScheme(appSettings.appTheme.colorScheme)
        }
        .sheet(isPresented: $showingNewProfile) {
            NewProfileSheet()
                .environmentObject(appSettings)
                .preferredColorScheme(appSettings.appTheme.colorScheme)
        }
        .sheet(item: $editingProfile) { profile in
            EditProfileSheet(profile: profile)
                .environmentObject(appSettings)
                .preferredColorScheme(appSettings.appTheme.colorScheme)
        }
        .sheet(isPresented: $showingPermissionHelp) {
            PermissionHelpSheet().preferredColorScheme(appSettings.appTheme.colorScheme)
        }
        .onAppear {
            guard PermissionService.shared.check() else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showingPermissionHelp = true }
                return
            }
            coordinator.changeAnchorDisplay(toUUID: appSettings.selectedDisplayUUID)
        }
        .onChange(of: appSettings.selectedDisplayUUID) { oldValue, newValue in
            coordinator.changeAnchorDisplay(toUUID: newValue)
            if appSettings.autoRelocateDock && oldValue != newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { coordinator.relocateDock() }
            }
        }
    }

    @ViewBuilder private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("DockAnchor")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Keep your dock anchored to one display")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
        .environmentObject(DockCoordinator.shared)
        .environmentObject(UpdateChecker())
}
