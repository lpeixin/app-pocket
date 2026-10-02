//
//  AppCatalog.swift
//  AppPocket
//
//  Owns the live list of applications installed on this Mac.
//

import AppKit
import Combine
import Foundation

@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var apps: [AppInfo] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var lastScanDuration: TimeInterval = 0
    /// Directories that exist but could not be read.
    @Published private(set) var unreadableRoots: [String] = []
    /// Bumped after every completed scan, so observers can react to "the list
    /// changed" without comparing arrays of two hundred structs.
    @Published private(set) var scanGeneration = 0
    /// Bundle identifiers of applications that are currently running, so the
    /// grid can show a running indicator without querying AppKit per tile.
    @Published private(set) var runningBundleIDs: Set<String> = []

    private var index: [String: AppInfo] = [:]
    private let watcher = DirectoryWatcher()
    private let roots: [URL]
    private var hasStarted = false
    private var currentScan: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []

    init(roots: [URL] = AppScanner.defaultRoots) {
        self.roots = roots
        watcher.onChange = { [weak self] in
            self?.refresh()
        }
    }

    var appCount: Int { apps.count }

    func app(id: String) -> AppInfo? {
        index[id]
    }

    /// Resolves many identifiers at once, preserving the requested order and
    /// skipping anything that is no longer installed.
    func apps(ids: [String]) -> [AppInfo] {
        ids.compactMap { index[$0] }
    }

    var isWatchingFileSystem: Bool { watcher.watchedPathCount > 0 }

    // MARK: - Lifecycle

    /// Starts the first scan and begins watching for installs and removals.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        observeRunningApplications()
        watcher.watch(roots)
        if lastScanDate == nil {
            refresh()
        }
    }

    func stop() {
        watcher.stop()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    // MARK: - Scanning

    /// Kicks off a scan. Repeated calls while one is running share the same task
    /// instead of queueing up redundant disk walks.
    @discardableResult
    func refresh() -> Task<Void, Never> {
        if let currentScan { return currentScan }

        isScanning = true
        let roots = self.roots
        let task = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                AppScanner.scan(roots: roots)
            }.value
            guard let self else { return }
            self.apply(outcome)
            self.currentScan = nil
        }
        currentScan = task
        return task
    }

    /// Awaits a scan, including one that was already in flight.
    func refreshAndWait() async {
        await refresh().value
    }

    private func apply(_ outcome: ScanOutcome) {
        apps = outcome.apps
        index = Dictionary(outcome.apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        unreadableRoots = outcome.unreadableRoots
        lastScanDuration = outcome.duration
        lastScanDate = Date()
        isScanning = false
        scanGeneration &+= 1
    }

    // MARK: - Running applications

    /// Tracks which applications are open, for the running indicator.
    private func observeRunningApplications() {
        refreshRunningApplications()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Resolve the weak reference to a strong `let` before hopping:
                // reading a captured `weak var` from concurrent code is an error
                // in the Swift 6 language mode.
                guard let self else { return }
                Task { @MainActor in
                    self.refreshRunningApplications()
                }
            }
            workspaceObservers.append(observer)
        }
    }

    func refreshRunningApplications() {
        runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
    }
}
