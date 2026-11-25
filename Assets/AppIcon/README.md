# Keyflow app icon

A graphite Command keycap resting on a satin aluminium keyboard deck,
rendered in Blender and clipped to the macOS icon shape.

| File | What it is |
| --- | --- |
| `AppIcon-1024.png` | The master: 1024 × 1024 with transparency, ⌘ and "command" |
| `AppIcon-Small-1024.png` | The small-size master: the ⌘ alone, used for 64 px and smaller |
| `Keycap-1024.png` | The keycap alone on transparency (for the DMG, website and so on) |
| `AppIcon.iconset/`, `AppIcon.icns` | Every macOS size; `Scripts/build-app.sh` copies the `.icns` into the app |
| `AppIcon.appiconset/` | The same images as an asset catalog icon set, for an Xcode project |
| `Preview.png` | All sizes on light and dark, with 32 and 16 px enlarged |

## Source

Run `Source/build-icon.sh` to rebuild everything. It needs Blender 5.x in
/Applications and takes a few minutes; pass a lower sample count for a quick
draft, for example `Source/build-icon.sh 64`.

- `legend.swift` draws the key legends as textures. The ⌘ is built from its
  geometry (a square whose sides continue into four loops) rather than taken
  from a font. "command" is set in SF Pro Medium.
- `keycap.py` models and renders the key in Blender: a tapered
  rounded-square body, a rounded top edge, a shallow concave dish, satin
  graphite with a printed legend, and soft studio area lights. In `deck` mode
  the key sits on aluminium; in `key` mode it stands alone over a shadow
  catcher.
- `icontool.swift` handles the image steps: exact box-filter downscaling,
  clipping to the icon shape, the size set and the preview sheet.
- `icon-shape-1024.png` is the outline macOS 26 and later use for app icons,
  read from the system's own rendering.

## Why the icon has a background

macOS 26 and later do not show a free-form icon as drawn. They shrink it onto
a grey rounded tile of their own; a transparent keycap was shown that way
here. The aluminium deck gives Keyflow a deliberate tile instead. Its outline
matches the system shape exactly, because anything else is boxed at large
sizes.

## Known limitation: 1x sizes of 32 px and under

On a non-Retina display, macOS still draws this icon on its grey tile at
16–32 pt (in list views and menus, for example). Retina displays use the 2x
images, which show normally, as do the Dock, the app switcher and Finder at
every size. Apps that avoid this at 1x ship an `Assets.car` compiled from an
Icon Composer `.icon` file. That needs Xcode's `actool`, and only the Command
Line Tools are installed here. With Xcode, build an `.icon` from
`AppIcon-1024.png` (or the layers in `Source`), add it to the target and set
`CFBundleIconName`.
