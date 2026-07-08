# SilasFlow: Recording Overlay + Settings Window — Design

Date: 2026-07-08 · Status: approved by user ("it looks right. you can build it")

## Goal

1. A Wispr Flow-style floating recording indicator so the user always knows the app
   is listening, and
2. a real Settings window replacing the cramped 300 px menu popover, with a usable
   dictionary editor and a one-click "teach it" loop.

User decisions (via AskUserQuestion): bottom-center pill · real Settings window
(General + Dictionary tabs) · include "Fix last transcript" teach loop.

## 1. Recording overlay

- `OverlayController` owns a borderless `NSPanel`: `.nonactivatingPanel`,
  `level = .statusBar`, transparent, `ignoresMouseEvents = true` (click-through),
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`. It NEVER takes
  focus — dictation target keeps keyboard focus.
- Position: bottom-center of the screen containing the mouse pointer,
  ~80 pt above the bottom edge. Size ≈ 210×54 pt.
- `WaveformView` (SwiftUI, hosted): dark translucent capsule with 12 vertical bars
  showing a scrolling history of live mic loudness. States:
  - **listening** — bars driven by `Recorder.onLevel` RMS values (~30 fps),
  - **processing** — bars settle into a gentle left-to-right shimmer,
  - **error** — brief red tint, then hide.
- Lifecycle: show on hotkey-down, switch to processing on hotkey-up, hide after
  paste/copy completes or on error. Overlay failures must never block the pipeline
  (it is purely cosmetic).
- `Recorder` already computes per-buffer RMS (added for the silent-mic fix); it
  gains an `onLevel` callback (audio thread → main-actor hop in controller).

## 2. Settings window

- SwiftUI `Settings` scene (standard macOS preferences window, opens with ⌘, or
  the menu's "Settings…" button via `openSettings`). App is `.accessory`, so
  opening also calls `NSApp.activate` to bring the window forward.
- **General tab:** hotkey preset picker · Whisper model picker · AI cleanup toggle
  + availability line · restore clipboard toggle · launch at login toggle ·
  permission status rows (mic / accessibility) with "Open Settings" buttons.
- **Dictionary tab:**
  - Vocabulary: editable word list (add field + list with delete buttons).
  - Corrections: two-column `Table` ("When it hears" → "Replace with") with +/−.
  - Storage format unchanged (comma-separated `vocabulary`, `heard = correct`
    lines in `corrections`) — existing user rules carry over; pipeline reads the
    same Settings keys.

## 3. Menu slim-down

Dropdown keeps only: status line · last transcript + outcome · "Fix last
transcript…" · "Test paste" · "Settings…" · Quit.

## 4. "Fix last transcript" teach loop

- Opens a small `Window` scene with the last transcript in an editable field.
- On save: word-level diff (common prefix/suffix trim) between original and
  edited text → middle segments become a `heard = correct` rule appended to
  corrections; corrected words are added to vocabulary; optional "paste fixed
  text" re-injects the corrected version.
- Empty/identical edits create no rule.

## Error handling

- Overlay: any panel failure is logged and ignored; dictation continues.
- Dictionary edits: empty terms and duplicate rules are dropped on save.
- Empty transcript now surfaces "Didn't catch that" in the menu (already shipped
  with the silent-mic fix).

## Out of scope

Streaming transcription, free-form hotkey recorder, App Store packaging.
