#if DEBUG
import Foundation
import SwiftData

/// Debug-only sample data. Launch with `-seedDemoData YES` to add a sample project.
enum DemoData {
    static func seedIfRequested(in context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "seedDemoData") else { return }
        let existing = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        guard !existing.contains(where: { $0.name == "Sample Project" }) else { return }

        let project = ProjectActions.createProject(named: "Sample Project", status: .active, in: context)
        project.colorHex = "#8B4FC9"
        project.githubURL = "https://github.com/example/sample"
        let lists = Dictionary(uniqueKeysWithValues: project.sortedLists.map { ($0.name, $0) })

        func add(_ text: String, _ list: String, by author: Author = .user) -> Item {
            ProjectActions.addItem(QuickAddParser.parse(text, allowPrefix: false), to: lists[list]!, in: project,
                                   context: context, by: author)
        }
        _ = add("Write the about page", "Tasks")
        let bug = add("Nav overlaps content on mobile !high", "Bugs")
        bug.stepsToReproduce = "1. Open the site on an iPhone\n2. Scroll down"
        bug.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)
        let lazy = add("Image lazy loading", "Tasks")
        lazy.subtasks = [Subtask(title: "Gallery page", isDone: true), Subtask(title: "Blog posts")]
        lazy.tags = ["perf"]
        _ = add("Contact form spam filter !medium", "Tasks", by: .claude)
        _ = add("Dark mode toggle", "Ideas")
        let done = add("Set up hosting", "Tasks")
        ProjectActions.complete(done)

        let paused = ProjectActions.createProject(named: "Game Prototype", status: .paused, in: context)
        paused.colorHex = "#1D9E75"
    }
}
#endif
