# SilasFlow — Build Plan (local, on-device Wispr Flow clone)

**Goal:** a macOS menu-bar app, written in Swift, that does fully on-device push-to-talk dictation
with AI cleanup — hold a hotkey, speak, release, and clean formatted text lands at your cursor in
any app. No cloud, no API keys.

**Target machine:** Apple Silicon, macOS 26 (Tahoe) — confirmed by this environment (Darwin 25.3).

---

## Architecture

```
┌──────────────────────────── SilasFlow.app (LSUIElement menu-bar) ─────────────────────────────┐
│                                                                                                 │
│   HotkeyManager ──(press)──▶ Recorder (AVAudioEngine, 16kHz mono) ──▶ [audio buffer]            │
│      │  KeyboardShortcuts combo (default)                                    │                  │
│      │  or CGEventTap hold-Right-Option (optional PTT)                       ▼                  │
│      └──(release)──────────────────────────────────────▶ Transcriber (WhisperKit / CoreML/ANE) │
│                                                                             │                   │
│                                                             raw transcript  ▼                   │
│                                                       CleanupEngine                             │
│                                                   1. Apple FoundationModels (@Generable)        │
│                                                   2. rule-based fallback                        │
│                                                                             │                   │
│                                                             clean text      ▼                   │
│                                                       TextInjector (clipboard + ⌘V via CGEvent, │
│                                                                    copy-only fallback)          │
│                                                                                                 │
│   MenuBarExtra UI · PermissionsManager (mic / accessibility / input-monitoring) · Settings      │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Package layout (Swift Package Manager executable → bundled into .app)

```
SilasFlow/
  Package.swift                 # SPM: executable target + WhisperKit dependency
  Sources/SilasFlow/
    SilasFlowApp.swift          # @main App, MenuBarExtra, app lifecycle
    Audio/Recorder.swift        # AVAudioEngine capture → 16kHz Float samples
    STT/Transcriber.swift       # WhisperKit wrapper (load model, transcribe buffer)
    Hotkey/HotkeyManager.swift  # KeyboardShortcuts combo + optional CGEventTap PTT
    Cleanup/CleanupEngine.swift # FoundationModels + rule-based
    Cleanup/RuleCleaner.swift   # deterministic filler/punctuation/caps
    Inject/TextInjector.swift   # clipboard + CGEvent ⌘V, restore clipboard
    Permissions/Permissions.swift  # mic/accessibility/input-monitoring checks + prompts
    UI/MenuContent.swift        # menu bar dropdown (status, model, hotkey, toggles)
    Settings/Settings.swift     # UserDefaults-backed config
    Support/Log.swift
  Resources/
    SilasFlow-Info.plist        # LSUIElement, usage strings
    SilasFlow.entitlements
  scripts/
    build_app.sh                # swift build + assemble .app bundle + codesign
    run.sh
  RESEARCH.md
  BUILD_PLAN.md
```

## Milestones (each ends in a compiling, runnable state)

- **M0 — Toolchain check.** Confirm `swift`, Xcode/SDK, macOS 26 SDK (for FoundationModels), chip. Pick SPM-executable-→-.app path (no Xcode GUI needed).
- **M1 — Menu-bar skeleton.** `MenuBarExtra` app with a mic icon + status text; `build_app.sh` produces a signed `SilasFlow.app` that launches with no Dock icon. *Verify: app appears in menu bar.*
- **M2 — Audio capture + hotkey.** KeyboardShortcuts combo starts/stops `AVAudioEngine` recording; menu shows "Recording…". Save WAV to temp for inspection. *Verify: audio file has real samples.*
- **M3 — WhisperKit STT.** Add WhisperKit via SPM, load `base.en`, transcribe the captured buffer, show transcript in the menu. *Verify: spoken words → correct text in a log.*
- **M4 — Text injection.** Clipboard + ⌘V CGEvent into the focused app, restore clipboard, copy-only fallback. *Verify: transcript lands in TextEdit.*
- **M5 — AI cleanup.** `CleanupEngine`: FoundationModels `@Generable` cleanup prompt (strip fillers, fix punctuation/caps, keep meaning) with rule-based fallback + a settings toggle. *Verify: "um so like the meeting is at four" → "The meeting is at four."*
- **M6 — Permissions + PTT + polish.** PermissionsManager guides mic/Accessibility/Input-Monitoring; optional CGEventTap hold-Right-Option PTT; settings for model, hotkey, cleanup on/off, launch-at-login. Notarize-ready signing.

## Key technical decisions (from RESEARCH.md)
- **STT:** WhisperKit (Swift-native, SPM, CoreML/ANE, streaming). Default `base.en`; large-v3-turbo optional.
- **Hotkey:** KeyboardShortcuts combo by default (no permission prompt); CGEventTap hold-Right-Option as optional true-PTT (Input Monitoring).
- **Injection:** clipboard + ⌘V (Accessibility); copy-only fallback.
- **Cleanup:** Apple FoundationModels first, rule-based fallback.
- **Packaging:** LSUIElement, Developer-ID/ad-hoc signed, direct distribution (avoids MAS Guideline 2.4.5 on Accessibility injection).

## Known constraints / risks
- FoundationModels needs Apple Intelligence enabled; rule-based path guarantees function without it.
- Accessibility grant needs an app relaunch to take effect (surface this in UI).
- WhisperKit downloads its model on first run (one-time network); after that fully offline.
- Full end-to-end verification needs user-granted TCC permissions in System Settings; the build/compile and per-component logic are verifiable autonomously, the live permission grants are documented for the user.
