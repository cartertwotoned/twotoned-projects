import Foundation

extension ClaudeTools {
    private static func object(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return schema
    }

    private static func string(_ description: String, enum values: [String]? = nil) -> [String: Any] {
        var s: [String: Any] = ["type": "string", "description": description]
        if let values { s["enum"] = values }
        return s
    }

    private static func strings(_ description: String) -> [String: Any] {
        ["type": "array", "items": ["type": "string"], "description": description]
    }

    private static let idField = string("Item id from list_items or get_project (the first 8 characters are enough).")
    private static let priorities = ["none", "low", "medium", "high", "urgent"]

    private static let detailFields: [String: Any] = [
        "notes": string("Notes in Markdown. Replaces existing notes."),
        "due_date": string("Due date as YYYY-MM-DD, or an empty string to clear it."),
        "tags": strings("Tags (replaces existing tags)."),
        "links": strings("URLs related to the item (replaces existing links)."),
        "steps_to_reproduce": string("Bug detail: steps to reproduce."),
        "expected_behavior": string("Bug detail: what should happen."),
        "actual_behavior": string("Bug detail: what actually happens."),
    ]

    static let definitions: [[String: Any]] = [
        [
            "name": "get_project",
            "title": "Get project",
            "description": "Overview of the TwoToned project linked to this folder: its lists, the current task (first item in Up Next) and the top of Up Next. Call this when you start working.",
            "inputSchema": object([:]),
            "annotations": ["readOnlyHint": true],
        ],
        [
            "name": "list_items",
            "title": "List items",
            "description": "List items in Up Next (default), in a specific list by name, all open items, or done items.",
            "inputSchema": object([
                "list": string("\"up_next\" (default), \"all\", \"done\", or a list name such as \"Bugs\"."),
                "include_details": ["type": "boolean", "description": "Include notes, subtasks and bug details."],
                "limit": ["type": "integer", "description": "Maximum items to return (default 50)."],
            ]),
            "annotations": ["readOnlyHint": true],
        ],
        [
            "name": "get_item",
            "title": "Get item",
            "description": "Full details of one item: notes, subtasks, links, attachments and bug details.",
            "inputSchema": object(["id": idField], required: ["id"]),
            "annotations": ["readOnlyHint": true],
        ],
        [
            "name": "add_item",
            "title": "Add item",
            "description": "Add an item to a list (default: the project's default list, usually Tasks). Use the Bugs list for bugs you find. New items are slotted into Up Next by priority unless you pass a position.",
            "inputSchema": object(detailFields.merging([
                "title": string("Short title."),
                "list": string("List name, e.g. \"Bugs\", \"Tasks\", \"Ideas\"."),
                "priority": string("Priority.", enum: priorities),
                "subtasks": strings("Checklist of subtasks."),
                "position": string("\"top\" makes it the current task, \"bottom\" puts it last. Omit to place by priority.",
                                   enum: ["top", "bottom"]),
            ]) { a, _ in a }, required: ["title"]),
        ],
        [
            "name": "update_item",
            "title": "Update item",
            "description": "Change an item's fields. Only the fields you pass are changed.",
            "inputSchema": object(detailFields.merging([
                "id": idField,
                "title": string("New title."),
                "priority": string("Priority.", enum: priorities),
                "append_notes": string("Text to add to the end of the existing notes."),
                "add_tags": strings("Tags to add."),
                "subtasks": strings("Replace the subtask checklist."),
                "add_subtasks": strings("Subtasks to add."),
                "complete_subtasks": strings("Subtasks to check off, by title or 1-based number."),
            ]) { a, _ in a }, required: ["id"]),
        ],
        [
            "name": "move_item",
            "title": "Move item",
            "description": "Move an item to another list and/or a new position in Up Next. Position \"top\" makes it the current task.",
            "inputSchema": object([
                "id": idField,
                "list": string("Destination list name."),
                "position": string("\"top\", \"bottom\", or a 1-based Up Next position such as \"3\"."),
            ], required: ["id"]),
        ],
        [
            "name": "complete_item",
            "title": "Complete item",
            "description": "Mark an item done. The next item in Up Next becomes the current task.",
            "inputSchema": object([
                "id": idField,
                "note": string("Optional note to add to the item, e.g. what was changed."),
            ], required: ["id"]),
        ],
        [
            "name": "reopen_item",
            "title": "Reopen item",
            "description": "Reopen a completed item. It goes back into its list and Up Next.",
            "inputSchema": object(["id": idField], required: ["id"]),
        ],
        [
            "name": "delete_item",
            "title": "Delete item",
            "description": "Permanently delete an item. Prefer complete_item for finished work; delete only when the user asks or it's a duplicate.",
            "inputSchema": object(["id": idField], required: ["id"]),
            "annotations": ["destructiveHint": true],
        ],
        [
            "name": "manage_lists",
            "title": "Manage lists",
            "description": "Create, rename, reorder or delete the project's lists, or choose whether a list feeds Up Next. Only delete empty lists.",
            "inputSchema": object([
                "action": string("What to do.", enum: ["create", "rename", "set_up_next", "reorder", "delete"]),
                "name": string("The list to act on (or the new list's name for create)."),
                "new_name": string("For rename."),
                "include_in_up_next": ["type": "boolean", "description": "For create or set_up_next."],
                "order": strings("For reorder: list names in the new order. Earlier lists win ties in Up Next."),
            ], required: ["action"]),
        ],
    ]
}
