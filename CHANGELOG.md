# Changelog

## 0.5.6

- Eliminate idle SwiftUI relayout loops caused by unconditional `@Published` mutations in `dismiss()` / `clearReplacement()` during global input and pointer movement.
- Replace the 4 background 10 Hz preview polling timers in `HomeView` with native `NSTrackingArea`.
- Remove CPU-only throttling on accurate Vision OCR, stop redundant fast-OCR reruns on blank areas, make OCR refinement cancellable, and run region screenshot OCR off the main thread in a `0o700` temporary directory.
- Fix `NSScreen.main!` force-unwrap crashes, Dock reopen after closing the main window, Esc dismissal inside the app, and preserve user-dragged card position when switching languages.
- Cache AI translations (Codex / Claude), stop spawning an auth-check subprocess before every translation, expand CLI/PATH discovery, harden translation prompts against prompt injection, and clean up cancelled/timed-out subprocesses via `terminationHandler`.
- Prevent "Download language pack" from overwriting the user's global target language setting, verify actual pack installation after the system dialog, fix OCR/language-pack readiness indicators, and align privacy copy with optional AI translation.
- Support CJK multi-line OCR sentence merging without inserting spaces, snap UTF-16 surrogate pair offsets safely, recognize short diacritic European UI labels, and clean up obsolete badge/menu dead code.

## 0.5.5

- Inline hover subtitle translation, optional local Codex / Claude CLI translation, interactive region screenshot OCR, and right-click translation in `SelectionEditor`.
- Keep leading and trailing whitespace of the selection when replacing it, so a double-clicked word with its trailing space no longer runs into the next word.
- Restore the clipboard only after the target editor has consumed the paste (up to 3 seconds) instead of after a fixed 800 ms, so slow editors can no longer paste the previous clipboard.
- Mark the temporary replacement clipboard as transient and auto-generated so clipboard managers skip it.
- Resolve the ⌘V key from the current keyboard layout (Dvorak, AZERTY and others) instead of assuming QWERTY.
- Read the selection only after a drag, double/triple click or shift-click; a plain click no longer reopens an old selection.
- Stop the 25 Hz pointer poll while translation is paused and nothing is on screen.
- Diagnostics no longer read or overwrite the user's settings.
- 94 core checks; hover-flow adds polling, clipboard lease and paste-key checks.

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
