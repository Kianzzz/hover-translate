# Changelog

## 0.3.2

- Extract full sentences across soft line wraps while respecting paragraph boundaries and UTF16 positions.
- Prefer a parent element with a precise text position over a shorter child label. Keep complete standalone text blocks as the fallback.
- Merge neighboring OCR lines within the same column and normal line spacing before sentence extraction; keep menus, paragraph gaps and adjacent columns separate.
- Expand the local OCR region to at most 1400 × 720 points and improve line refinement hit testing. Text outside this visible region cannot be completed.
- Grow translation content up to 260 points tall, then scroll; keep compact short-text cards.
- Add 44 core checks and 5 real Vision OCR fixture checks.


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
