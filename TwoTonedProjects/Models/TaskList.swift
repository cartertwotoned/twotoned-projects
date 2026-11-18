import Foundation
import SwiftData

@Model
final class TaskList {
    var id: UUID = UUID()
    var name: String = ""
    /// Rank of the list. Lower ranks come first in tabs and win ties in Up Next ordering.
    var sortIndex: Int = 0
    /// Whether open items from this list appear in the project's Up Next list.
    var includeInUpNext: Bool = true
    /// New items in this list show the bug detail fields by default.
    var isBugList: Bool = false
    /// Where quick-add puts items when no list is specified.
    var isDefault: Bool = false
    var symbol: String = "checklist"
    var project: Project?

    @Relationship(deleteRule: .cascade, inverse: \Item.list)
    var items: [Item]? = []

    init(name: String, sortIndex: Int, includeInUpNext: Bool = true, isBugList: Bool = false,
         isDefault: Bool = false, symbol: String = "checklist") {
        self.id = UUID()
        self.name = name
        self.sortIndex = sortIndex
        self.includeInUpNext = includeInUpNext
        self.isBugList = isBugList
        self.isDefault = isDefault
        self.symbol = symbol
    }

    var openItems: [Item] { (items ?? []).filter { !$0.isCompleted } }

    static let symbolChoices = [
        "checklist", "ladybug", "lightbulb", "sparkles", "star", "flag",
        "hammer", "paintbrush", "doc.text", "shippingbox", "bolt", "tray",
    ]
}
