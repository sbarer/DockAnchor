//
//  SettingsView.swift
//  DockAnchor
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var coordinator: DockCoordinator
    @EnvironmentObject var updateChecker: UpdateChecker
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    startupSection
                    dockBehaviorSection
                    hotCornersSection
                    interfaceSection
                    displayArrangementSection
                    footerSection
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
        }
        .frame(width: 420, height: 680)
        .background(.background)
    }

    @ViewBuilder private var headerRow: some View {
        HStack {
            Text("Settings").font(.title2).fontWeight(.bold)
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder private var startupSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Startup & Background").font(.subheadline).fontWeight(.semibold)
            HStack {
                Text("Start at Login").font(.callout)
                Spacer()
                Toggle("", isOn: $appSettings.startAtLogin)
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            HStack {
                Text("Run in Background").font(.callout)
                Spacer()
                Toggle("", isOn: $appSettings.runInBackground)
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder private var dockBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dock Behavior").font(.subheadline).fontWeight(.semibold)
            HStack {
                Text("Auto-Move Dock").font(.callout)
                Spacer()
                Toggle("", isOn: $appSettings.autoRelocateDock)
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            HStack {
                Text("Default Anchor").font(.callout)
                Spacer()
                Picker("", selection: $appSettings.defaultAnchorDisplay) {
                    ForEach(DefaultAnchorDisplay.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            Text("Used when anchor display is unavailable")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder private var hotCornersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hot Corners").font(.subheadline).fontWeight(.semibold)
            Text("When enabled, corner areas are excluded from edge blocking so macOS hot corners still fire.")
                .font(.caption).foregroundColor(.secondary)
            ForEach(coordinator.displays) { display in
                HStack {
                    Text(display.name).font(.callout)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { appSettings.isHotCornersPreserved(forDisplayUUID: display.uuid) },
                        set: { appSettings.setHotCornersPreserved($0, forDisplayUUID: display.uuid) }
                    ))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder private var interfaceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Interface").font(.subheadline).fontWeight(.semibold)
            HStack {
                Text("Show Menu Bar Icon").font(.callout)
                Spacer()
                Toggle("", isOn: $appSettings.showStatusIcon)
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            HStack {
                Text("Hide from Dock").font(.callout)
                Spacer()
                Toggle("", isOn: $appSettings.hideFromDock)
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            HStack {
                Text("Theme").font(.callout)
                Spacer()
                Picker("", selection: $appSettings.appTheme) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder private var displayArrangementSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Display Arrangement").font(.subheadline).fontWeight(.semibold)
            DisplayArrangementView(
                displays: coordinator.displays,
                selectedDisplayUUID: $appSettings.selectedDisplayUUID,
                maxHeight: 150
            )
            Text("\(coordinator.displays.count) display(s) detected")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder private var footerSection: some View {
        VStack(spacing: 4) {
            Button(action: {
                if let url = URL(string: "https://buymeacoffee.com/bwya77") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack(spacing: 4) { Text("☕"); Text("Buy Me a Coffee") }
            }
            .buttonStyle(.link)
            Text("Version \(appVersion)")
                .font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3"
    }
}
