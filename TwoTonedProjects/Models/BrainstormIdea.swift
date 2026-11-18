import Foundation
import SwiftData

nonisolated struct BrainstormPoint: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var text: String
}

/// A rough project idea: a top-level bullet with sub-bullets.
/// It can be converted into a real project, with every bullet going into its Ideas list.
@Model
final class BrainstormIdea {
    var id: UUID = UUID()
    /// The top bullet. Not assumed to be a name: it can be an idea in itself.
    var text: String = ""
    var points: [BrainstormPoint] = []
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    init(text: String, sortIndex: Int) {
        self.id = UUID()
        self.text = text
        self.sortIndex = sortIndex
        self.createdAt = .now
    }

    /// Everything that goes into the new project's Ideas list, top bullet first.
    var allIdeas: [String] {
        ([text] + points.map(\.text))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
