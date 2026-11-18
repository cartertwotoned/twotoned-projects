<img src="images/app-icon.png" width="72" align="right" alt="">

# Backups

TwoToned Projects can back a project up to **iCloud Drive**, so you have copies away from your Mac. Use one to keep working on another computer, or to get everything back if a drive fails.

## Back up a project

Open the project and click the **cloud button** in the toolbar. You can also right-click the project in the sidebar and choose **Back up now**, or use **Project settings › Backups**, which also shows when the last backup was made.

Backups are organized like this:

```
iCloud Drive
└── TwoToned Backups
    └── My Project
        ├── Backup 1
        ├── Backup 2
        └── Backup 3        ← the newest has the highest number
            ├── Files/                  a copy of the project's linked folder(s)
            ├── TwoToned Data.json      the project's lists and items
            └── TwoToned Summary.md     a readable summary
```

Each project's folder is created on its first backup. A backup only gets its final "Backup N" name once it's complete, so a backup interrupted halfway never looks finished.

## Settings

All in **Settings › Backups**:

| Setting | What it does |
|---|---|
| **Backup folder** | Where backups go. Default: *iCloud Drive › TwoToned Backups*. |
| **Folder files** | **Everything in the folder** (default): an exact copy, including git-ignored files, dependencies, build output, git history, and hidden files.<br>**Skip build, dependency, and git-ignored files**: smaller and quicker to upload.<br>**TwoToned data only**: just the lists and items. |
| **Keep up to** | How many backups to keep per project (default 10). Past that, the oldest is deleted. Or turn on **Keep every backup**. |

When the backup folder is on the same disk as your projects, copies are nearly instant and don't use extra space on your Mac. iCloud then uploads them in the background. Large folders, like ones with `node_modules`, can take a while to upload the first time.

## Automatic backups

In **Project settings › Backups**, turn on **Back up automatically when items are completed**. It's off by default and set per project.

- It backs up at most once every **30 minutes** (adjustable).
- It waits a few seconds after a completion, so checking off several items at once makes one backup.
- Items completed by Claude count too.

## Restoring

There's no restore button yet. To restore:

- **Files:** copy them back from a backup's `Files` folder in Finder.
- **Lists and items:** in **Settings › Data**, choose **Import…** and pick the backup's `TwoToned Data.json`. Importing adds the project if it isn't already in the app, and never overwrites anything.
