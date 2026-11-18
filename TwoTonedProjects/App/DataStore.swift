import Foundation
import SwiftData

/// Where the app keeps its data. Everything TwoToned Projects stores lives under
/// one folder so it can be fully removed later.
nonisolated enum DataStore {
    static var dataDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "TwoToned Projects", directoryHint: .isDirectory)
    }

    /// Copies of files attached from outside a project's linked folders.
    static var attachmentsDirectory: URL {
        dataDirectory.appending(path: "Attachments", directoryHint: .isDirectory)
    }

    static var storeURL: URL {
        dataDirectory.appending(path: "Projects.store")
    }

    static let schema = Schema([Project.self, TaskList.self, Item.self, ActivityEntry.self, BrainstormIdea.self])

    static func makeContainer() throws -> ModelContainer {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let config = ModelConfiguration("TwoTonedProjects", schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: config)
    }
}
