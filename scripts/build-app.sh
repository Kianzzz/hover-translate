#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
build_dir="${HOVER_TRANSLATE_BUILD_DIR:-$HOME/Library/Caches/HoverTranslate/build}"
swift build --scratch-path "$build_dir" -c release
binary_dir="$(swift build --scratch-path "$build_dir" -c release --show-bin-path)"
app_dir="${HOVER_TRANSLATE_APP_DIR:-$HOME/Applications/浮译.app}"
# Keep temporary packages out of LaunchServices and the user's permission picker.
if [[ "$app_dir" == "$HOME/Library/Caches/HoverTranslate/"*.app ]]; then
  print -u2 'Temporary builds must use a .bundle suffix; only the installed app uses .app.'
  exit 1
fi
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/HoverTranslate" "$app_dir/Contents/MacOS/HoverTranslate"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
if [[ -f "$project_dir/Assets/AppIcon.icns" ]]; then
  cp "$project_dir/Assets/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
fi
# Documents can carry file-provider Finder metadata, which codesign rejects.
# Remove metadata only from this newly generated bundle, immediately before signing.
xattr -cr "$app_dir"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$project_dir/Info.plist")"
codesign --force --sign - --identifier "$bundle_id" "$app_dir"
printf 'Built: %s\n' "$app_dir"
