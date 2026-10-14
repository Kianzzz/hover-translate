#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
build_dir="${HOVER_TRANSLATE_BUILD_DIR:-$HOME/Library/Caches/HoverTranslate/build}"
mkdir -p "$build_dir/checks"
swiftc Sources/HoverTranslate/TextLogic.swift Tests/HoverTranslateTests/TextLogicTests.swift -o "$build_dir/checks/CoreChecks"
"$build_dir/checks/CoreChecks"
