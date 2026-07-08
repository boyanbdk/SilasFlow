# SilasFlow — Research: How Wispr Flow works & how to recreate it fully on-device

> Synthesized from a deep-research run (5 search angles, ~15 sources fetched, 112 extracted
> claims, 68 verified high/medium confidence, 6 refuted). The workflow's final synthesis step
> crashed on a retry cap, so this report was reconstructed from the verified claim journal.
> Date: 2026-07-08. Target: macOS 26 (Tahoe) on Apple Silicon.

---

## 1. What Wispr Flow actually is (the spec we're matching)

Wispr Flow (wisprflow.ai, formerly "Flow") is a **push-to-talk AI dictation** app. The user flow:

1. Put the cursor anywhere in any app.
2. **Hold a hotkey** (`fn` by default on desktop — push-to-talk, *not* always-on listening).
3. Speak naturally.
4. Release → clean, formatted text is inserted **at the cursor, system-wide** (Slack, Gmail, VS Code, Docs — 40+ apps shown in their carousel).

### The pipeline (verified)
```
mic (local capture) → [CLOUD] speech-to-text → [CLOUD] LLM cleanup/format → text returned → inserted at cursor
```

- **Cloud-only. No offline mode.** Multiple independent sources confirm "all transcription happens in the cloud," it "cannot function without an internet connection," and it relies on OpenAI + Meta models. *This is the single biggest thing we deliberately change — we go fully local.*
- **"AI Auto Edits"** (their real feature name, verbatim on the homepage): "Rambled thoughts become clear, perfectly formatted text, without the filler words or typos." Their docs break this into:
  - **Backtrack** — removes disfluencies, false starts, and self-corrections (if you say "meet at 3… no, 4pm" it writes "4pm").
  - **Smart Formatting** — grammar, punctuation, capitalization, disfluency cleanup.
- **Command Mode** — speak an instruction to transform selected text ("make this more formal", "turn into bullet points", "summarize"). This is the LLM/tone layer.
- **Context-aware** — reads the active window/app and adapts tone (casual for Slack, professional for email).
- **Personal dictionary** learns custom words; snippet library; 100+ languages with auto-detect.
- **Perf claims:** ~700 ms end-to-end latency, ~90% accuracy, marketed ~220 wpm (~4× typing). Pricing: free 2k words/week, Pro ~$12–15/mo.

### Our target subset (per user's choices)
Fully on-device · **global-hotkey push-to-talk dictation** + **AI cleanup/formatting** · Swift native menubar app. (Command Mode, multi-device sync, mobile, personal-dictionary learning = out of scope for v1.)

---

## 2. On-device speech-to-text on Apple Silicon (the engine choice)

Independent benchmark (`github.com/anvanvan/mac-whisper-speedtest`, MacBook Pro **M4 24 GB**, "large" model, **batch** transcription time of a fixed file — lower = faster):

| Implementation | Time (s) | Notes |
|---|---|---|
| fluidaudio-coreml (Parakeet TDT) | **0.19** | fastest; CoreML/ANE |
| parakeet-mlx | 0.50 | |
| mlx-whisper | 1.02 | |
| insanely-fast-whisper | 1.13 | |
| whisper.cpp (CoreML, 4 threads) | 1.23 | Metal/CoreML |
| lightning-whisper-mlx | 1.82 | |
| **whisperkit** (native Swift bridge) | **2.22** | Swift-native, CoreML/ANE |
| whisper-mps | 5.37 | |
| faster-whisper (CPU int8) | 6.96 | **no Metal on Mac → CPU-only, slowest** |

Key facts (verified):
- **Whisper accuracy (WER, clean English):** tiny ~9%, base ~6.5%, small ~4.5%, medium ~3.8%, large-v3 ~3.2%. Doubles/triples on noisy/accented audio. whisper.cpp and faster-whisper share OpenAI weights → identical accuracy.
- **`small` ≈ `medium` quality at 2–3× the speed** → best real-time Whisper tier for dictation.
- **Latency is a batch (record-then-transcribe) model** for Whisper: perceived latency ≈ audio length + inference + ~150 ms overhead. A 5 s utterance on `small`/M3 ≈ 5.7 s total. True sub-second *streaming* Whisper is hard on M1-class hardware.
- **Parakeet (FluidAudio CoreML)** is dramatically faster and supports streaming. ⚠️ *Correction from refuted claim:* the "110× RTF" figure is **batch**, not streaming; real streaming Parakeet is ~29× RTFx on M2 — still far above real time.
- **WhisperKit** (Argmax): Swift-native, CoreML on the Apple Neural Engine, **SPM one-line dependency**, **streaming** (emits partial results), MIT license, auto-downloads a device-appropriate model, ships tiny→large-v3 incl. a compressed large-v3 (~626 MB). Needs Xcode 16+, macOS 14+. Slower than whisper.cpp/Parakeet in raw batch, but **by far the easiest to embed in pure Swift**.
- **Apple SpeechAnalyzer / SpeechTranscriber** (macOS 26): on-device, streaming, word timestamps; WER 14.0 @ speed-factor 70 on M4. But: model must be **downloaded** (not pre-installed), only **10 languages**, **no custom vocabulary**. For comparison on the same M4: WhisperKit `base.en` = WER 15.2 @ 111; Argmax Pro `parakeet-v2` = WER 11.7 @ 359.

**Existence proofs (real shipping apps doing exactly this):**
- **VoiceInk** — pure Swift (99.7%), embeds **whisper.cpp**, 100% offline, GPLv3, macOS 14.4+, also supports **Parakeet via the FluidAudio Swift package**, app-detection/context-awareness, **hotkeys via CGEventTap** (⚠️ *not* the KeyboardShortcuts package — a source claimed that but the actual repo migrated off it to a custom CGEventTap).
- **VocaMac** — Swift/SwiftUI, **WhisperKit** (CoreML+ANE), `MenuBarExtra`, `AVAudioEngine`, bundles the Tiny model for offline-out-of-the-box, clipboard+Cmd-V injection, CGEventTap hold-Right-Option PTT, Developer ID signed + notarized, macOS 13+.
- **Rasala/dictate** — MLX `whisper-large-v3` + local LLM cleanup (Qwen2.5-3B-4bit / Phi-3-mini via MLX-LM), hold-Left-Option PTT, VAD, 100% local (Python).
- **JustDictate** — Parakeet TDT 0.6B v3 via ONNX (CPU, no GPU), hold-Right-Command PTT, clipboard + CGEvent Cmd-V, ~0.5 s latency, no AI cleanup (Python).

**➡️ Decision for SilasFlow:** **WhisperKit** as the primary STT (native Swift, SPM, streaming, ANE, proven by VocaMac). Default model `base.en`/`small` for latency; allow large-v3-turbo. Keep **FluidAudio/Parakeet** as a documented speed-upgrade path.

---

## 3. Global hotkey / push-to-talk capture (Swift)

Apple DTS engineer Quinn ("The Eskimo!", forum thread 735223) enumerates exactly three options:

| Approach | Permission needed | Notes |
|---|---|---|
| **CGEventTap** | **Input Monitoring** (TCC) | DTS **preferred** — cleanest TCC story via `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()`. "A bit tricky from Swift." **Only reliable way to detect a bare modifier-key hold** (fn / Right-Option) for true PTT. Used by VoiceInk, VocaMac, OpenLess. |
| **Carbon `RegisterEventHotKey`** | **none** | DTS: "can't honestly recommend it" (legacy Carbon). Registers an exact key *combo*, not a bare modifier hold. |
| **NSEvent global monitor** | Accessibility | Enumerated but not preferred. |
| **KeyboardShortcuts** package (Sindre Sorhus) | **none / no dialog** | Wraps `RegisterEventHotKey`; **fully sandboxed, MAS-compatible**; `onKeyDown()`/`onKeyUp()` enable hold-to-talk on a *combo*; used by Dato/Plash/Lungo. MIT, macOS 10.15+. |

**➡️ Decision:** ship **both modes**. Default = **KeyboardShortcuts** combo (e.g. ⌥Space) with `onKeyDown`/`onKeyUp` → *zero permission prompts*, easiest. Optional "**Hold Right Option**" true-PTT mode = **CGEventTap** (requires Input Monitoring). This mirrors what shipping apps do and lets us avoid the Input-Monitoring prompt for users who don't need bare-modifier PTT.

---

## 4. Inserting text into the focused app

| Method | Permission | Reliability |
|---|---|---|
| **Clipboard + synthesized ⌘V** (CGEvent) | **Accessibility** | Most common in shipping apps (JustDictate, VocaMac). Simple, reliable. Clobbers clipboard → save/restore. |
| **CGEvent per-character keystrokes** | Accessibility | Works everywhere but slow for long text; Unicode quirks. |
| **AXUIElement** (set focused element value) | Accessibility | Cleanest when it works; OpenLess uses it as *first* tier. **⚠️ Got WhisperPad rejected from the Mac App Store under Guideline 2.4.5.** |

OpenLess's battle-tested chain: **AX focused-element → clipboard+⌘V → copy-only fallback**, streaming char-by-char to reduce perceived latency.

**➡️ Decision:** **clipboard + ⌘V via CGEvent** (save & restore the user's clipboard), with a **copy-only fallback** if Accessibility is denied. Needs Accessibility. *Gotcha: the Accessibility grant only takes effect after the app is quit & relaunched.*

---

## 5. The AI cleanup/formatting step — fully local

Options for the local LLM cleanup:

- **Apple Foundation Models framework** (macOS 26, WWDC 2025) — on-device `SystemLanguageModel` (~3B params, 2-bit QAT weights, ~1 GB), explicitly built for **refinement / summarization / entity extraction** (exactly our task), with **`@Generable` guided generation** (force structured Swift output) and **tool calling**. `SystemLanguageModel.default`, network "not in the call path." **Requires macOS 26 + Apple-Intelligence-capable Apple Silicon.**
- **Local LLM via MLX-LM** (Qwen2.5-3B-4bit / Phi-3-mini) — fastest local runtime is **MLX (~230 tok/s, 5–7 ms/token on M2 Ultra)**; 4-bit 3B ≈ 1.6 GB. ⚠️ MLX cold-start ≈ **31 s**; llama.cpp loads <0.5 s cached; Ollama 20–40 tok/s. Proven by Rasala/dictate.
- **Rule-based fallback** — deterministic filler-word/disfluency removal + capitalization/punctuation spacing. Zero deps, instant, always available.

**➡️ Decision:** three-tier, in priority order:
1. **Apple Foundation Models** (`SystemLanguageModel`) with a `@Generable`-guided cleanup prompt — **the user is on macOS 26 (Darwin 25.3), Apple Silicon → this is available and free of extra downloads.**
2. **Rule-based cleanup** as the guaranteed baseline (and for when Apple Intelligence is off).
3. (Optional, documented) local Ollama/MLX model for heavier reformatting.

---

## 6. Permissions & packaging

Three TCC permissions, added incrementally:
- **Microphone** — always (audio capture via `AVAudioEngine`). `NSMicrophoneUsageDescription`.
- **Accessibility** — for CGEvent ⌘V text injection. *Takes effect only after quit + relaunch.*
- **Input Monitoring** — only for the CGEventTap bare-modifier PTT mode. Check/request via `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()`.

Packaging:
- **`LSUIElement` menu-bar app** (no Dock icon), SwiftUI `MenuBarExtra`.
- Launch-at-login via `SMAppService.loginItem`.
- **Mac App Store caveat:** Guideline **2.4.5** restricts Accessibility text-injection → for MAS you'd ship a clipboard-only variant (user presses ⌘V) or distribute directly with **Developer ID signing + notarization** (what VocaMac does). We target **direct distribution**.
- WhisperKit build reqs: **Xcode 16+, macOS 14+**.

---

## 7. Sources (verified during research)

- **wisprflow.ai** homepage + docs.wisprflow.ai (AI Auto Edits, Backtrack, Smart Formatting, Command Mode, "works on any app or device").
- `github.com/anvanvan/mac-whisper-speedtest` — 9-implementation Apple-Silicon ASR benchmark.
- `github.com/argmaxinc/WhisperKit` — Swift-native Whisper (MIT).
- `github.com/FluidInference/FluidAudio` — Parakeet CoreML Swift package + benchmarks.
- `github.com/beingpax/VoiceInk` — Swift/whisper.cpp offline dictation (GPLv3).
- `github.com/jatinkrmalik/vocamac` — Swift/WhisperKit menubar dictation.
- `github.com/gowtham-ponnana/JustDictate` — Parakeet/ONNX PTT dictation.
- `github.com/Rasala/dictate` — MLX Whisper + local-LLM cleanup.
- `github.com/Open-Less/openless` — CGEventTap + AX/clipboard insertion fallback chain.
- `github.com/sindresorhus/KeyboardShortcuts` — global-hotkey package.
- Apple Developer Forums thread **735223** (Quinn, global-hotkey guidance + Input Monitoring APIs).
- Apple ML Research — "Updates to Apple's On-Device and Server Foundation Language Models" (2025).
- Apple `developer.apple.com/documentation/FoundationModels` (SystemLanguageModel, @Generable, Tool).
- arXiv **2511.05502** — "Production-Grade Local LLM Inference on Apple Silicon" (MLX vs llama.cpp vs Ollama…).
- macOS 26 SpeechAnalyzer/SpeechTranscriber benchmark writeup; WhisperPad App-Store-2.4.5 rejection writeup.
