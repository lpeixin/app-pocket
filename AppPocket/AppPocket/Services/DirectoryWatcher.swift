//
//  DirectoryWatcher.swift
//  AppPocket
//
//  Watches application folders for installs and removals.
//

import Foundation

/// Wraps a `DispatchSource` per watched directory.
///
/// The previous implementation re-scanned every three seconds and rebuilt every
/// icon along the way. Watching for actual directory changes is both cheaper
/// and more responsive: a newly installed app shows up within about a second.
@MainActor
final class DirectoryWatcher {
    /// Coalesces the burst of events an install produces.
    private static let debounceInterval: Duration = .milliseconds(900)

    private var sources: [DispatchSourceFileSystemObject] = []
    private let queue = DispatchQueue(label: "com.liupeixin.AppPocket.fsmonitor", qos: .utility)
    private var debounceTask: Task<Void, Never>?
    private var pollTimer: Timer?

    /// Called on the main actor after the debounce window.
    var onChange: (() -> Void)?

    private(set) var watchedPathCount = 0

    func watch(_ urls: [URL]) {
        stop()
        for url in urls {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .extend, .attrib],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor in
                    self?.scheduleNotification()
                }
            }
            source.setCancelHandler {
                close(descriptor)
            }
            source.resume()
            sources.append(source)
        }

        watchedPathCount = sources.count

        // If the kernel refused every watch, fall back to a slow poll so the
        // list still refreshes without the user having to ask.
        if sources.isEmpty {
            startFallbackPolling()
        }
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        pollTimer?.invalidate()
        pollTimer = nil
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        watchedPathCount = 0
    }

    private func scheduleNotification() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: DirectoryWatcher.debounceInterval)
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }

    private func startFallbackPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.onChange?()
            }
        }
    }
}
