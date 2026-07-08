# SilasFlow — how to install it (with Claude Code)

Hey! This is a little Mac app that lets you **hold a key, talk, and have your words typed
out wherever your cursor is** — all on your own machine, nothing sent to the cloud.

You don't need to know how to code to install it. If you have **Claude Code**, it will do
the whole build for you. This page walks you through it.

---

## What you need

- A **Mac with Apple Silicon** (M1/M2/M3/M4 — basically any Mac from 2020 onward).
- **Claude Code** installed and working.
- ~10 minutes, mostly waiting on downloads the first time.

That's it. You do **not** need to install Xcode yourself or run any commands by hand —
Claude Code handles all of that.

---

## Step 1 — Get the code

Clone this repository to your Mac. If you're not sure how, just open Claude Code in a
folder where you keep projects and paste this:

> Clone https://github.com/boyanbdk/SilasFlow and open the folder.

---

## Step 2 — Let Claude Code build and run it

Open Claude Code **inside the SilasFlow folder** and paste this prompt:

> Build the SilasFlow macOS app from this source using `scripts/build_app.sh`, install
> whatever toolchain is needed (e.g. Xcode Command Line Tools), then launch it and walk
> me through granting the Microphone and Accessibility permissions it needs. If anything
> fails, diagnose and fix it, then try again.

Claude Code will:
1. Install the build tools if they're missing (this may trigger a one-time, multi-GB
   Command Line Tools download — that's normal, just let it finish).
2. Compile the app.
3. Launch it and guide you through the two macOS permission prompts.

**Want to check it's safe first?** Before building, you can also ask Claude Code:

> Read through this app's source and tell me exactly what it does, what data it touches,
> and why it wants Microphone and Accessibility access. Flag anything that looks unsafe.

Since you have the full source, this is a real audit — not a guess about a mystery file.

---

## Step 3 — Use it

- **Hold ⌥Space** (Option + Space), speak, then release. Your words get typed at your cursor.
- The **menu-bar icon** shows the state: mic = ready, filled mic = listening, waveform = transcribing.
- Click the menu-bar icon to change the hotkey, pick a different speech model, or toggle cleanup.

The first time you dictate, it downloads a small speech model (~145 MB) once, then works
fully offline forever after.

For the full feature list and settings, see the main [README](README.md).

---

## Why we're giving you the source code, not the finished app

This is deliberate, and it's for **your** safety — not because we're making you do extra work.

1. **An app you build yourself is trusted by your Mac; a file I send you is not.**
   macOS blocks apps from "unidentified developers" (this app isn't registered with
   Apple's paid signing program). If I handed you the pre-built `.app`, macOS would warn
   you it might be dangerous, and you'd have to *right-click → Open* to bypass that
   warning. That's the exact move scammers tell people to do to run malware — a habit we
   don't want to teach you. When Claude Code builds it **on your own machine**, there's no
   warning and nothing to bypass.

2. **You can actually verify what you're running.** A binary is an opaque blob — you have
   to just trust it. Source code can be read. You (or Claude Code, on your behalf) can
   inspect exactly what this app does before it ever runs. That's the whole point of the
   "check it's safe first" prompt above.

3. **This app asks for powerful permissions**, and you should be able to see why.
   It needs the **Microphone** (to hear you) and **Accessibility** (to type text into
   other apps for you). Those are high-trust permissions — an app with Accessibility can
   control other apps. Because you have the source, that access isn't something you take on
   faith; it's something you can confirm.

4. **Updates are cleaner and safer.** When something improves, you just pull the latest
   code and rebuild (Claude Code does both) — no re-downloading binaries from somewhere and
   re-approving scary warnings each time.

In short: **building from source is the more private, more verifiable, and less
warning-prone way to run this** — which fits an app whose whole selling point is that it
keeps your voice and text on your own machine.

---

Questions or something broke? Ask Claude Code to debug it — it has the full source and can
usually fix build or permission issues on the spot.
