import Foundation
import CoreServices

/// Caches folder scans per project and rescans in the background.
@MainActor
@Observable
final class FolderStore {
    static let shared = FolderStore()

    private(set) var scans: [UUID: FolderScan] = [:]
    private(set) var scanning: Set<UUID> = []
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    func scan(for project: Project) -> FolderScan? { scans[project.id] }

    func isScanning(_ project: Project) -> Bool { scanning.contains(project.id) }

    /// Rescans the project's folders off the main thread. Cancels any scan already running.
    func refresh(_ project: Project) {
        let id = project.id
        let roots = project.folders.map(\.url)
        tasks[id]?.cancel()
        guard !roots.isEmpty else {
            scans[id] = nil
            return
        }
        scanning.insert(id)
        tasks[id] = Task {
            let result = await Task.detached(priority: .utility) { FolderScanner.scan(roots) }.value
            guard !Task.isCancelled else { return }
            scans[id] = result
            scanning.remove(id)
            tasks[id] = nil
        }
    }

    /// Uses the cached scan if it's recent, otherwise rescans.
    func refreshIfStale(_ project: Project, maxAge: TimeInterval = 60) {
        if let existing = scans[project.id], Date.now.timeIntervalSince(existing.scannedAt) < maxAge { return }
        refresh(project)
    }

    /// Frees cached results for projects that aren't on screen.
    func forget(_ project: Project) { scans[project.id] = nil }
}

/// Watches folders with FSEvents while a view that shows them is on screen.
/// Changes inside ignored build/dependency folders don't trigger anything.
nonisolated final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void

    init?(paths: [String], onChange: @escaping @MainActor () -> Void) {
        guard !paths.isEmpty else { return nil }
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagIgnoreSelf)
        guard let stream = FSEventStreamCreate(nil, { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
            let relevant = paths.prefix(count).contains { path in
                !path.split(separator: "/").contains { component in
                    let name = String(component)
                    return FolderScanner.ignoredDirectories.contains(name)
                }
            }
            if relevant { MainActor.assumeIsolated { watcher.onChange() } }
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.0, flags)
        else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
