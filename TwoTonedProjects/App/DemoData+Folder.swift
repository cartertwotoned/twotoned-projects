#if DEBUG
import Foundation
import SwiftData

extension DemoData {
    /// Debug-only: launch with `-linkDemoFolder /path` to link a folder to "Sample Project".
    static func linkFolderIfRequested(in context: ModelContext) {
        guard let path = UserDefaults.standard.string(forKey: "linkDemoFolder"), !path.isEmpty else { return }
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let name = UserDefaults.standard.string(forKey: "linkDemoProject") ?? "Sample Project"
        let project = projects.first(where: { $0.name == name })
            ?? ProjectActions.createProject(named: name, status: .active, in: context)
        guard !project.folders.contains(where: { $0.path == path }) else { return }
        project.folders.append(FolderLink(url: URL(fileURLWithPath: path, isDirectory: true),
                                          isPrimary: project.folders.isEmpty))
    }
}
#endif
