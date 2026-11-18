<img src="images/app-icon.png" width="72" align="right" alt="">

# Claude Code

TwoToned Projects can connect to [Claude Code](https://claude.com/claude-code). Once connected, Claude can read a project's lists, log bugs it finds, and check off what it finishes, while you keep using Claude Code exactly as before, in the terminal or the Claude app.

## Connect

1. **Link the project's folder.** Open the project, then **Project settings › Folders › Link folder…**, and choose the folder you work in with Claude Code.
2. **Connect.** Open **Settings › Claude Code** and click **Connect to Claude Code**. The status changes to **Connected**.
3. **Start or restart a Claude Code session** in that folder. Sessions load their tools when they start, so one that was already running needs to be restarted. Reopening an older conversation works too, and its history is kept.

Then just ask, for example: *"What's on my Up Next?"*, *"Add a bug: the export button does nothing"*, or *"Mark the login task done."*

You only connect once. After that, every new Claude Code session picks it up, in any linked folder.

## What Claude can do

Claude only ever sees **the project whose linked folder contains the folder the session is working in**. Every other project is out of reach. If a folder isn't linked to any project, Claude can't see anything and will tell you to link it.

Within that project, Claude can:

- read the project, Up Next, any list, or completed items
- add items, with priority, notes, tags, subtasks, due dates, and bug details
- edit, move, reorder, complete, reopen, and delete items
- create, rename, reorder, and remove empty lists

Everything Claude adds or changes gets a purple **Claude** badge, and each change is listed in the project's **Activity** tab. Changes appear in the app right away.

## How it works

The app includes a small helper, `twotoned-mcp`, inside `TwoToned Projects.app`. Connecting registers it with Claude Code as a user-level tool server named `twotoned-projects`, using Claude Code's own `claude mcp add` command. If the `claude` command can't be found, the app adds that one entry to `~/.claude.json` instead.

When a session starts, Claude Code launches the helper in that session's folder. The helper passes requests to TwoToned Projects over a private connection on your Mac, opening the app in the background if it isn't running. Nothing is written to your project folders, and nothing leaves your Mac.

If you move the app (for example into Applications), it updates the connection automatically the next time it opens.

## Disconnect

Open **Settings › Claude Code** and click **Disconnect**. This removes the `twotoned-projects` entry from Claude Code's settings. Sessions that are already running keep the tools until they restart.

Disconnecting doesn't change any of your projects. You can connect again any time.

## Troubleshooting

| Problem | Fix |
|---|---|
| Claude says no project is linked | Link the folder in **Project settings › Folders**. Claude matches the folder its session started in, or any folder inside it. |
| Claude doesn't have the TwoToned tools | Restart the Claude Code session after connecting. |
| Status says "Points at another copy of the app" | Click **Update connection**, or just reopen the app from where it now lives. |
| `claude mcp list` doesn't show it | Click **Disconnect**, then **Connect to Claude Code** again. |
