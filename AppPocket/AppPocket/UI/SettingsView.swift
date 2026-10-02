//
//  SettingsView.swift
//  AppPocket
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var catalog: AppCatalog

    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    @State private var statusMessage: String?
    @State private var isConfirmingReset = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("settings.general", systemImage: "gearshape") }
            appearanceTab
                .tabItem { Label("settings.appearance", systemImage: "paintbrush") }
            dataTab
                .tabItem { Label("settings.data", systemImage: "externaldrive") }
            aboutTab
                .tabItem { Label("settings.about", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 430)
        .onAppear { launchAtLoginEnabled = LaunchAtLogin.isEnabled }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Toggle("settings.closeAfterLaunch", isOn: closeAfterLaunchBinding)
                    .help("settings.closeAfterLaunchHelp")
            } header: {
                Text("settings.launchBehaviour")
            }

            Section {
                Toggle("settings.launchAtLogin", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled) { _, newValue in
                        // Deferred so the store is not mutated during a view update.
                        Task { @MainActor in applyLaunchAtLogin(newValue) }
                    }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("settings.startup")
            }

            Section {
                Toggle("settings.menuBarExtra", isOn: menuBarBinding)
                Toggle("settings.globalHotKey", isOn: hotKeyEnabledBinding)

                if store.settings.globalHotKeyEnabled {
                    Picker("settings.hotKeyCombination", selection: hotKeyBinding) {
                        ForEach(HotKeySpec.presets, id: \.self) { spec in
                            Text(spec.displayString).tag(spec)
                        }
                    }
                }
            } header: {
                Text("settings.quickAccess")
            } footer: {
                Text("settings.hotKeyFooter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Section {
                Picker("settings.iconSize", selection: iconSizeBinding) {
                    ForEach(AppIconSize.allCases) { size in
                        Text(LocalizedStringKey(size.titleKey)).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("settings.automaticColumns", isOn: automaticColumnsBinding)

                if store.settings.effectiveColumnCount != nil {
                    Stepper(value: columnCountBinding, in: 3...12) {
                        Text(
                            String(
                                format: NSLocalizedString("settings.columnsPerRow", comment: "Columns"),
                                store.settings.columnCount
                            )
                        )
                    }
                }
            } header: {
                Text("settings.grid")
            }

            Section {
                Picker("settings.sortMode", selection: sortModeBinding) {
                    ForEach(AppSortMode.allCases) { mode in
                        Label(LocalizedStringKey(mode.titleKey), systemImage: mode.symbolName).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("settings.sorting")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Data

    private var dataTab: some View {
        Form {
            Section {
                HStack {
                    Button("settings.export") { exportLibrary() }
                    Spacer()
                    Button("settings.import") { importLibrary() }
                }
                Button("settings.revealDataFile") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.fileLocation])
                }
            } header: {
                Text("settings.backup")
            } footer: {
                Text(store.fileLocation.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("settings.resetAll", role: .destructive) {
                    isConfirmingReset = true
                }
                Text("settings.resetWarning")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("settings.reset")
            }
        }
        .formStyle(.grouped)
        .alert("settings.resetConfirmTitle", isPresented: $isConfirmingReset) {
            Button("action.reset", role: .destructive) {
                store.reset()
                statusMessage = NSLocalizedString("settings.resetDone", comment: "")
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("settings.resetConfirmMessage")
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 14) {
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            VStack(spacing: 3) {
                Text("AppPocket")
                    .font(.system(size: 15, weight: .semibold))
                Text(
                    String(
                        format: NSLocalizedString("settings.version", comment: "Version"),
                        Bundle.main.shortVersion
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider().frame(width: 260)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                statRow("settings.stat.apps", "\(catalog.appCount)")
                statRow(
                    "settings.stat.lastScan",
                    catalog.lastScanDate.map {
                        $0.formatted(date: .omitted, time: .standard)
                    } ?? NSLocalizedString("settings.stat.never", comment: "")
                )
                statRow(
                    "settings.stat.scanDuration",
                    String(format: "%.0f ms", catalog.lastScanDuration * 1000)
                )
                statRow(
                    "settings.stat.watching",
                    catalog.isWatchingFileSystem
                        ? NSLocalizedString("settings.stat.active", comment: "")
                        : NSLocalizedString("settings.stat.polling", comment: "")
                )
            }
            .font(.system(size: 11))

            if !catalog.unreadableRoots.isEmpty {
                Text(
                    String(
                        format: NSLocalizedString("settings.unreadableRoots", comment: "Unreadable folders"),
                        catalog.unreadableRoots.joined(separator: ", ")
                    )
                )
                .font(.caption2)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statRow(_ titleKey: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(titleKey)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .monospacedDigit()
        }
    }

    // MARK: - Bindings

    private var closeAfterLaunchBinding: Binding<Bool> {
        Binding(
            get: { store.settings.closeAfterLaunch },
            set: { value in store.updateSettings { $0.closeAfterLaunch = value } }
        )
    }

    private var menuBarBinding: Binding<Bool> {
        Binding(
            get: { store.settings.showMenuBarExtra },
            set: { value in store.updateSettings { $0.showMenuBarExtra = value } }
        )
    }

    private var hotKeyEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.settings.globalHotKeyEnabled },
            set: { value in store.updateSettings { $0.globalHotKeyEnabled = value } }
        )
    }

    private var hotKeyBinding: Binding<HotKeySpec> {
        Binding(
            get: { store.settings.globalHotKey },
            set: { value in store.updateSettings { $0.globalHotKey = value } }
        )
    }

    private var iconSizeBinding: Binding<AppIconSize> {
        Binding(
            get: { store.settings.iconSize },
            set: { value in store.updateSettings { $0.iconSize = value } }
        )
    }

    private var sortModeBinding: Binding<AppSortMode> {
        Binding(
            get: { store.settings.sortMode },
            set: { value in store.updateSettings { $0.sortMode = value } }
        )
    }

    private var automaticColumnsBinding: Binding<Bool> {
        Binding(
            get: { store.settings.effectiveColumnCount == nil },
            set: { automatic in
                store.updateSettings { settings in
                    settings.columnCount = automatic ? 0 : 6
                }
            }
        )
    }

    private var columnCountBinding: Binding<Int> {
        Binding(
            get: { store.settings.effectiveColumnCount ?? 6 },
            set: { value in store.updateSettings { $0.columnCount = value } }
        )
    }

    // MARK: - Actions

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
            store.updateSettings { $0.launchAtLogin = enabled }
        } catch {
            launchAtLoginError = String(
                format: NSLocalizedString("settings.launchAtLoginFailed", comment: "Login item failure"),
                error.localizedDescription
            )
            // Put the switch back where the system actually is.
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
        }
    }

    private func exportLibrary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "AppPocket-library.json"
        panel.title = NSLocalizedString("settings.export", comment: "")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
            statusMessage = NSLocalizedString("settings.exportDone", comment: "")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func importLibrary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = NSLocalizedString("settings.import", comment: "")
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        do {
            try store.importDocument(from: try Data(contentsOf: url))
            statusMessage = NSLocalizedString("settings.importDone", comment: "")
        } catch {
            statusMessage = String(
                format: NSLocalizedString("settings.importFailed", comment: ""),
                error.localizedDescription
            )
        }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
