#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
build_dir="${HOVER_TRANSLATE_BUILD_DIR:-$HOME/Library/Caches/HoverTranslate/build}"
app_dir="${HOVER_TRANSLATE_APP_DIR:-$HOME/Applications/浮译.app}"
# Keep temporary packages out of LaunchServices and the user's permission picker.
if [[ "$app_dir" == "$HOME/Library/Caches/HoverTranslate/"*.app ]]; then
  print -u2 'Temporary builds must use a .bundle suffix; only the installed app uses .app.'
  exit 1
fi
signing_identity="${HOVER_TRANSLATE_SIGNING_IDENTITY:-HoverTranslate Local Signing}"
if [[ "$signing_identity" == "-" ]]; then
  if [[ "$app_dir" != *.bundle ]]; then
    print -u2 '临时签名仅用于测试包。安装浮译需要固定的代码签名身份。'
    exit 1
  fi
elif ! security find-identity -v -p codesigning | awk -v id="$signing_identity" '
  { hash=$2; sub(/^[^"]*"/, ""); sub(/".*$/, ""); if ($0 == id || hash == id) found=1 }
  END { exit !found }'; then
  print -u2 "钥匙串中没有可用的代码签名身份：$signing_identity。已停止更新，现有安装保留。"
  exit 1
fi
swift build --scratch-path "$build_dir" -c release
binary_dir="$(swift build --scratch-path "$build_dir" -c release --show-bin-path)"
mkdir -p "${app_dir:h}"
package_dir="$(mktemp -d "${app_dir:h}/.hovertranslate.XXXXXXXX")"
trap 'rm -rf "$package_dir"' EXIT
package="$package_dir/${app_dir:t}"
mkdir -p "$package/Contents/MacOS" "$package/Contents/Resources"
cp "$binary_dir/HoverTranslate" "$package/Contents/MacOS/HoverTranslate"
cp "$project_dir/Info.plist" "$package/Contents/Info.plist"
if [[ -f "$project_dir/Assets/AppIcon.icns" ]]; then
  cp "$project_dir/Assets/AppIcon.icns" "$package/Contents/Resources/AppIcon.icns"
fi
# Documents can carry file-provider Finder metadata, which codesign rejects.
# Remove metadata only from this newly generated bundle, immediately before signing.
xattr -cr "$package"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$project_dir/Info.plist")"
codesign --force --sign "$signing_identity" --identifier "$bundle_id" "$package"
codesign --verify --strict "$package"

if [[ -e "$app_dir" ]]; then
  # A migrated installation may be ad hoc. For subsequent certificate-signed
  # releases, check the new app against the old app's actual requirement.
  signature="$(codesign -dv "$app_dir" 2>&1)"
  if [[ "$signature" != *"Signature=adhoc"* ]]; then
    requirement="$(codesign -dr - "$app_dir" 2>&1 | sed -n 's/^designated => //p')"
    [[ -n "$requirement" ]]
    codesign --verify --strict -R "=$requirement" "$package"
  fi
  python3 - "$package" "$app_dir" <<'PYTHON'
import ctypes
import os
import sys

libc = ctypes.CDLL(None, use_errno=True)
if libc.renamex_np(os.fsencode(sys.argv[1]), os.fsencode(sys.argv[2]), 2):
    raise OSError(ctypes.get_errno(), "Could not swap application bundles")
PYTHON
else
  mv "$package" "$app_dir"
fi
printf 'Built: %s\n' "$app_dir"
