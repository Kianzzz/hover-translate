#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
build_dir="${HOVER_TRANSLATE_BUILD_DIR:-$HOME/Library/Caches/HoverTranslate/build}"
mkdir -p "$build_dir/checks"
swiftc Sources/HoverTranslate/TextLogic.swift Sources/HoverTranslate/DiagnosticCheck.swift Tests/HoverTranslateTests/TextLogicTests.swift -o "$build_dir/checks/CoreChecks"
"$build_dir/checks/CoreChecks"

# A failed diagnostic must exit 1 (not SIGTRAP/SIGABRT) and explain the failure.
swiftc Sources/HoverTranslate/DiagnosticCheck.swift Tests/HoverTranslateTests/DiagnosticExitTests.swift -o "$build_dir/checks/DiagnosticExitChecks"
"$build_dir/checks/DiagnosticExitChecks"
check_status=0
"$build_dir/checks/DiagnosticExitChecks" --fail 2> "$build_dir/checks/diagnostic-failure.txt" || check_status=$?
if [[ "$check_status" != 1 ]] || ! /usr/bin/grep -q 'CHECK FAILED:.*Deliberate diagnostic failure' "$build_dir/checks/diagnostic-failure.txt"; then
  print -u2 "Diagnostic failure handling check failed (exit $check_status)"
  exit 1
fi
print 'Diagnostic failure exits normally with status 1 and an explicit error.'
