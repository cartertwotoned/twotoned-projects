<img src="images/app-icon.png" width="72" align="right" alt="">

# Uninstalling

On a Mac, dragging an app to the Trash doesn't remove the data and settings it has stored. TwoToned Projects has a button that does, so nothing is left behind.

## The right way

1. **Back up anything you want to keep** (optional). Use **Settings › Data › Export…** for a full backup file, or [back up](backups.md) individual projects.
2. Open **Settings › Data** and click **Remove all data…** under **Uninstall**.
3. Confirm with **Remove everything and quit**.
4. Drag **TwoToned Projects** from your Applications folder to the Trash.

That's it: nothing is left on your Mac.

## What "Remove all data" deletes

- Every project, list, item, activity entry, and brainstorm idea
- Copies of attached files stored by the app
- Your settings and shortcuts
- The **Claude Code connection** (the `twotoned-projects` entry in Claude Code's settings)
- The app's caches and saved window state

## What it doesn't touch

- **Your project folders.** The app only ever read them.
- **Backups** in your backup folder (for example *iCloud Drive › TwoToned Backups*). They're your files. Delete them in Finder if you don't need them.
- **Exported files** you saved yourself.

## If you already deleted the app

Reinstall it, open it, and use **Remove all data…** as above. Or remove these by hand:

| What | Where |
|---|---|
| App data | `~/Library/Application Support/TwoToned Projects` |
| Settings | `~/Library/Preferences/com.twotonedstudios.projects.plist` |
| Claude Code connection | In Terminal: `claude mcp remove --scope user twotoned-projects` |
