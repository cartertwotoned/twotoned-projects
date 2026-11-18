import Foundation
import SwiftUI

/// Ordering rules for items.
///
/// Every item has a `rank`. All views show items sorted by rank, so a manual drag
/// order is never re-sorted behind the user's back. The priority rule is used only to
/// decide where *new* (or reopened) items land, and when the user asks to re-sort.
enum Ordering {
    /// The default rule: priority (urgent first), then list rank (bugs first), then oldest first.
    static func ruleLess(_ a: Item, _ b: Item) -> Bool {
        if a.priorityRaw != b.priorityRaw { return a.priorityRaw > b.priorityRaw }
        let ra = a.list?.sortIndex ?? Int.max
        let rb = b.list?.sortIndex ?? Int.max
        if ra != rb { return ra < rb }
        return a.createdAt < b.createdAt
    }

    static func byRank(_ items: [Item]) -> [Item] {
        items.sorted { a, b in
            a.rank == b.rank ? a.createdAt < b.createdAt : a.rank < b.rank
        }
    }

    /// Combined list of open items from lists that are included in Up Next.
    static func upNext(for project: Project) -> [Item] {
        byRank(project.openItems.filter { $0.list?.includeInUpNext ?? false })
    }

    static func currentTask(for project: Project) -> Item? {
        upNext(for: project).first
    }

    static func openItems(in list: TaskList) -> [Item] {
        byRank(list.openItems)
    }

    /// The set of items a given item is ordered among (Up Next, or its own list if excluded).
    private static func peers(of item: Item, in project: Project) -> [Item] {
        let includes = item.list?.includeInUpNext ?? false
        return byRank(project.openItems.filter { other in
            other !== item && (includes ? (other.list?.includeInUpNext ?? false) : other.list === item.list)
        })
    }

    /// Gives a new or reopened item a rank so it sits where the priority rule says,
    /// relative to its neighbours, without disturbing anyone else's manual order.
    static func place(_ item: Item, in project: Project) {
        let others = peers(of: item, in: project)
        if let index = others.firstIndex(where: { ruleLess(item, $0) }) {
            let next = others[index].rank
            let prev = index > 0 ? others[index - 1].rank : next - 2
            item.rank = (prev + next) / 2
        } else {
            item.rank = (others.last?.rank ?? 0) + 1
        }
        normalizeIfCrowded(project)
    }

    /// Moves the item to the very top of Up Next, making it the current task.
    static func makeCurrent(_ item: Item, in project: Project) {
        let first = upNext(for: project).first { $0 !== item }
        item.rank = (first?.rank ?? 0) - 1
    }

    /// Puts an open item at a 0-based position in Up Next (or its own list if excluded).
    static func moveTo(_ item: Item, position: Int, in project: Project) {
        let others = peers(of: item, in: project)
        if others.isEmpty { return }
        if position <= 0 {
            item.rank = others[0].rank - 1
        } else if position >= others.count {
            item.rank = others[others.count - 1].rank + 1
        } else {
            item.rank = (others[position - 1].rank + others[position].rank) / 2
        }
        normalizeIfCrowded(project)
    }

    /// Applies a drag-and-drop move within an ordered subset of items.
    ///
    /// The subset's existing rank "slots" are reassigned in the new order, so items
    /// outside the subset (e.g. other lists) keep their relative positions.
    static func move(_ subset: [Item], from source: IndexSet, to destination: Int) {
        var reordered = subset
        reordered.move(fromOffsets: source, toOffset: destination)
        assignSlots(of: subset, to: reordered)
    }

    /// Re-sorts a subset by the priority rule, reusing its rank slots.
    static func resort(_ subset: [Item]) {
        assignSlots(of: subset, to: subset.sorted(by: ruleLess))
    }

    private static func assignSlots(of original: [Item], to newOrder: [Item]) {
        var slots = original.map(\.rank).sorted()
        // Guarantee strictly increasing slots even if ranks collided.
        for i in slots.indices.dropFirst() where slots[i] <= slots[i - 1] {
            slots[i] = slots[i - 1] + 0.001
        }
        for (item, slot) in zip(newOrder, slots) where item.rank != slot {
            item.rank = slot
        }
    }

    /// Re-spaces ranks when repeated midpoint insertion gets too precise.
    private static func normalizeIfCrowded(_ project: Project) {
        let sorted = byRank(project.allItems)
        let crowded = zip(sorted, sorted.dropFirst()).contains { abs($1.rank - $0.rank) < 1e-6 && $0.rank != $1.rank }
        guard crowded else { return }
        for (i, item) in sorted.enumerated() { item.rank = Double(i) }
    }
}
