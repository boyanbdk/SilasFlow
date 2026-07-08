# SilasFlow

Fully on-device push-to-talk dictation for macOS — a local, private Wispr Flow clone.
**Hold a hotkey, speak, release** → clean text is pasted at your cursor in any app.
No cloud, no API keys; audio and text never leave this Mac.

> **Just want to install and use it?** See **[FOR_FRIENDS.md](FOR_FRIENDS.md)** — a
> non-technical, step-by-step guide to building it with Claude Code (no coding required),
> plus why this is shipped as source rather than a pre-built app.

## How it works

```
hold ⌥Space → mic (AVAudioEngine, 16 kHz) → WhisperKit (CoreML/ANE, on-device)
     → cleanup (Apple on-device LLM, rule-based fallback) → paste at cursor (⌘V)
```

- **STT:** [WhisperKit](https://github.com/argmaxinc/WhisperKit) — `base.en` by default (~0.4 s for 8 s of speech, warm). Model auto-downloads on first run, then works offline.
- **Cleanup tier 1:** Apple FoundationModels on-device LLM (needs macOS 26 + **Apple Intelligence enabled**) — removes fillers, applies spoken self-corrections ("3pm… no wait, 4pm" → "4pm"), fixes punctuation.
- **Cleanup tier 2 (always on):** rule-based filler removal + capitalization/punctuation. Used automatically when Apple Intelligence is off.
- **Hotkey:** Carbon `RegisterEventHotKey` — no Accessibility/Input-Monitoring permission needed. Presets: ⌥Space (default), ⌃⌥Space, ⌥⌘D, ⌥`.
- **Insertion:** clipboard + synthesized ⌘V, previous clipboard restored. If Accessibility isn't granted, text stays on the clipboard (press ⌘V yourself).

## Build & run

```bash
scripts/build_app.sh release   # swift build + assemble + ad-hoc sign
open SilasFlow.app
```

Requires: Apple Silicon, macOS 14+ (macOS 26 for AI cleanup), Xcode Command Line Tools.

## First-run setup (one-time)

1. **Microphone** — click *Allow* on the dialog at first launch (or System Settings → Privacy & Security → Microphone → SilasFlow).
2. **Accessibility** (for auto-paste) — System Settings → Privacy & Security → Accessibility → add/enable **SilasFlow**, then **quit & relaunch the app** (the grant only takes effect after relaunch).
3. **Apple Intelligence** (optional, unlocks AI cleanup) — System Settings → Apple Intelligence & Siri → turn on. Without it, rule-based cleanup runs.
4. First dictation with a new model downloads it from Hugging Face (one-time; `base.en` ≈ 145 MB), cached under `~/Documents/huggingface/`.

## Usage

- Hold **⌥Space**, speak, release. Menu-bar icon: mic = ready, filled mic = listening, waveform = transcribing.
- Menu: switch hotkey preset, Whisper model (tiny/base/small/large-v3-turbo), toggle AI cleanup, toggle clipboard restore, see last transcript.

## Headless pipeline test

```bash
.build/release/SilasFlow --selftest speech.wav [--no-ai] [--model small.en]
```

## Known limitations (v1)

- Batch transcription (transcribes on release, not streaming-while-talking).
- Hotkey presets only (no free-form recorder — Carbon API, CLT-only build).
- Self-correction cleanup ("no wait, 4pm") needs Apple Intelligence; rules alone keep both phrases.
- Direct distribution only (Accessibility paste-injection violates Mac App Store guideline 2.4.5).

See [RESEARCH.md](RESEARCH.md) for the deep-research findings this design is based on, and [BUILD_PLAN.md](BUILD_PLAN.md) for the architecture/milestones.
