# App icon

The app icon is an Icon Composer file: `TwoTonedProjects/AppIcon.icon`. It uses the layers in this folder, which are each a 1024 × 1024 transparent canvas with the checkmark centered.

| File | Contents |
|---|---|
| `checkmark-blue.svg` / `.png` | Short stroke, blue `#1FB0E6` |
| `checkmark-purple.svg` / `.png` | Long stroke, purple `#8B4FC9` |
| `checkmark-combined.svg` / `.png` | Both strokes on one layer, blue over purple |

The SVGs are best for editing: they stay sharp at any size and recolor cleanly for the dark and tinted icon styles.

## Editing the icon

1. Open `TwoTonedProjects/AppIcon.icon` in Icon Composer.
2. Make your changes and save it in the same place.
3. Rebuild the app. Xcode picks up the new icon automatically.

If the Dock keeps showing an old icon after you reinstall, it's using a cached copy. Make sure only one copy of the app exists, then restart the Dock (`killall Dock`). If that isn't enough, clear the icon caches in `$(getconf DARWIN_USER_CACHE_DIR)` (`com.apple.dock.iconcache` and `com.apple.iconservices*`) and restart the Dock again.

## Branding

`../Branding/twotoned-studios-logo.png` is the TwoToned Studios logo. The brand colors are blue `#1FB0E6` and purple `#8B4FC9`.
