#!/usr/bin/env bash
#
# Build a double-clickable Prince.app from the SwiftPM product.
#
#   Scripts/make-app.sh [output path]
#
# SwiftPM has no notion of an app bundle, so this assembles one: the executable, the Info.plist,
# the resource bundle `Bundle.module` looks for, and an icon. Ad-hoc signed, which is enough for
# the machine that built it and not enough to hand to anyone else — see ARCHITECTURE.md §2 on
# why that is as far as this can honestly go.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/PrinceOfPersia"
CONFIG="${CONFIG:-release}"
APP="${1:-$ROOT/build/Prince of Persia.app}"

echo "==> building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$PACKAGE"
BIN="$(swift build -c "$CONFIG" --package-path "$PACKAGE" --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Prince" "$APP/Contents/MacOS/Prince of Persia"

# `Bundle.module` searches `Bundle.main.resourceURL` among others, so Contents/Resources is where
# the SwiftPM resource bundle has to land. Without it the app launches and immediately dies on a
# missing level file.
shopt -s nullglob
for bundle in "$BIN"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
  echo "    bundled $(basename "$bundle")"
done
shopt -u nullglob

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Prince of Persia</string>
  <key>CFBundleDisplayName</key><string>Prince of Persia</string>
  <key>CFBundleExecutable</key><string>Prince of Persia</string>
  <key>CFBundleIdentifier</key><string>local.prince-of-persia.port</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

echo "==> icon"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

# A designed icon if there is one at the repo root, otherwise the game’s own cover art
# centre-cropped to a square. The fallback is what shipped before appicon.png existed, and it is
# kept so the script still works in a checkout that does not have the artwork.
if [ -f "$ROOT/appicon.png" ]; then
  sips -z 1024 1024 "$ROOT/appicon.png" --out "$TMP/master.png" >/dev/null
  echo "    from appicon.png"
else
  sips -c 400 400 "$PACKAGE/Sources/PoPCore/Resources/gfx/cover.png" --out "$TMP/master.png" >/dev/null
  echo "    from the game's cover art (no appicon.png at the repo root)"
fi
for spec in "16 16" "16 32" "32 32" "32 64" "128 128" "128 256" "256 256" "256 512" "512 512" "512 1024"; do
  set -- $spec
  base="$1"; px="$2"
  name="icon_${base}x${base}"
  [ "$px" != "$base" ] && name="${name}@2x"
  sips -z "$px" "$px" "$TMP/master.png" --out "$ICONSET/${name}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> signing (ad hoc)"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "    (codesign failed; the app still runs locally)"

# ---------------------------------------------------------------------------
# Does it actually stand on its own?
# ---------------------------------------------------------------------------
# Copy the app somewhere unrelated - a different directory, with a space in the name - and run it
# from there. This is the check that matters: an app that loads its resources out of the source
# tree it was built in works perfectly until somebody moves it, and an absolute path baked in at
# compile time is invisible until then too.
echo
echo "==> checking it runs from somewhere else"
CHECK="$(mktemp -d)/A Folder With Spaces"
mkdir -p "$CHECK"
cp -R "$APP" "$CHECK/"
MOVED="$CHECK/$(basename "$APP")/Contents/MacOS/Prince of Persia"
if "$MOVED" --level 3 --trace --ticks 1 >/dev/null 2>&1; then
  echo "    yes - it loads level 3 from $CHECK"
else
  echo "    NO - the app cannot find its own resources once moved" >&2
  rm -rf "$(dirname "$CHECK")"
  exit 1
fi
rm -rf "$(dirname "$CHECK")"

# And nothing under the hood should name a directory on the machine that built it.
if strings "$APP/Contents/MacOS/Prince of Persia" | grep -q '^/Users/'; then
  echo "    WARNING: the binary names an absolute path under /Users" >&2
fi

echo
echo "built $APP"
du -sh "$APP" | sed "s/^/    /"
