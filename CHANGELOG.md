# Changelog

## 0.3.1

- Place the hover badge near the closest text edge, with a compact fallback for imprecise accessibility bounds.
- Keep the badge reachable while the pointer approaches it; dismiss on departure and tolerate brief pauses.
- Add placement and directional hover regression checks.
- Report diagnostic failures with an explicit error and exit status 1 instead of triggering macOS Problem Reporter. This fixes test-run error popups; it is not a claim that all runtime crashes are resolved.
- Validate both successful and deliberately failing diagnostic commands.

## 0.3.0

First public source release.

- Native macOS hover translation with a system-appearance-aware green badge.
- Unified selection popup with original / Chinese / English tabs.
- Preview-before-replace for verified editable selections; normal paste preserves the editor's undo behavior where supported.
- Local Accessibility, Vision OCR and Apple Translation integration.
- Core, lifecycle and replacement-safety checks.

Earlier local prototypes, personal debugging notes, screenshots and build products are not included.
