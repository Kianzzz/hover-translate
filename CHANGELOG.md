# Changelog

## Unreleased

- Handle ScreenCaptureKit callbacks that return neither an image nor an error without entering the generated async bridge that crashes on a missing image.
- Pause hover and selection capture during system sleep, display sleep and inactive user sessions. Clear stale capture tasks and cards, refresh permissions on return, and wait two seconds for display recovery.
- Reset capture after display reconfiguration and skip OCR on inactive or sleeping displays.
- Add screenshot callback and cancellation checks, overlapping sleep/session state checks, and a workspace-notification recovery diagnostic.

## 0.4.0

- Add native-language and target-language settings (both default to Simplified Chinese). Hover only shows the badge for text outside the native language.
- Detect the source language automatically across 20 languages. CJK is decided by script; short Latin text defaults to English unless clearly another language. Text already in the target language falls back to the native language or English.
- Selections in any language now show the badge first and open the card on hover; the shortcut and menu still open it directly.
- Simplify the card to source + translation, removing the original / Chinese / English tabs.
- Add per-language pack status and download in settings, a System Settings shortcut with real download progress, and refresh on returning to the app.
- Only run OCR when Accessibility exposes no text, extend fast OCR to English, French, German, Spanish, Italian and Portuguese, and drop OCR results that fail a spelling check. This stops native text from being misread as random languages.
- Keep the hover badge beside the pointer for multi-line blocks and padded controls (bounds taller than about two lines, or edges more than 24 points away).
- Sign with a stable local identity when available so privacy grants survive rebuilds.
- Redesign the main window, settings and translation card; settings use pull-down menus that open below the field.
- 84 core checks.

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
