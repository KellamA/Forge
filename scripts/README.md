# Scripts

These scripts generate the bundled datasets and the images in `docs/`. The app doesn't need them at build
time, because their output is already committed. They're here so the datasets can be regenerated.

| Script | Output |
| --- | --- |
| `build_catalog.py` | `Forge/Resources/exercises.json` from free-exercise-db's `dist/exercises.json` |
| `normalize_bodymap.py` | `Forge/Resources/bodymap.json` from the `react-native-body-highlighter` npm package |
| `make_icon.swift` | The light, dark and tinted app icons in `AppIcon.appiconset` |
| `make_docs_images.py` | Rounded README screenshots and `docs/hero.png` from raw simulator captures |

## Regenerating the datasets

```bash
mkdir -p scripts/downloads && cd scripts/downloads
curl -sSLO https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json
curl -sSL https://registry.npmjs.org/react-native-body-highlighter/-/react-native-body-highlighter-3.2.0.tgz | tar -xz
cd ../..
python3 -I scripts/build_catalog.py scripts/downloads/exercises.json Forge/Resources/exercises.json
python3 -I scripts/normalize_bodymap.py scripts/downloads/package/dist Forge/Resources/bodymap.json
```

## Regenerating the app icon

```bash
swift scripts/make_icon.swift Forge/Assets.xcassets/AppIcon.appiconset
```

## README screenshots

Capture full-resolution screenshots with `xcrun simctl io booted screenshot <name>.png` into a folder, then:

```bash
python3 -I scripts/make_docs_images.py <raw screenshots dir> docs Forge/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

`make_docs_images.py` needs Pillow and uses the SF Pro Rounded system font on macOS.
