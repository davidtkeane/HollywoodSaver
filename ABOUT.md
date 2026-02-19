# About HollywoodSaver

**Version:** 4.8.0 (Final Free Version)
**Platform:** macOS 15+ (Apple Silicon — M1/M2/M3/M4)
**License:** MIT
**Source:** Single Swift file (~3000 lines), compiled with `swiftc` — no Xcode project

---

## What is HollywoodSaver?

HollywoodSaver is a native macOS menu bar app that turns your Mac into a video screensaver and **live wallpaper engine**. Play looping videos, GIFs, and built-in effects fullscreen — or run them behind your windows as a living desktop. Built with Swift in a single file, no Xcode project needed.

---

## Features

| Feature | Description |
|---------|-------------|
| **Screensaver Mode** | Fullscreen video, cursor hidden, dismiss with Escape/click/mouse |
| **Live Wallpaper Mode** | Ambient mode + reduced opacity = animated wallpaper behind all your windows |
| **Ambient Mode** | Play on any screen while you keep working — built-in, external, or all |
| **Multi-Screen** | Built-in, external, all screens — your choice |
| **Video + GIF** | Supports `.mp4`, `.mov`, `.m4v`, and `.gif` files |
| **Matrix Rain** | Built-in Matrix digital rain effect — no video file needed |
| **Matrix Settings** | Color theme, speed, characters, density, font size, trail length |
| **Rain Effects** | Two independent Matrix Rain modes — behind windows (wallpaper) and over windows (transparent overlay). Both fully click-through, with separate opacity sliders |
| **Floating Clock** | Always-on-top clock overlay — 6 colors, 3 sizes, 4 corner positions, optional date, screen selection, auto-restore |
| **Break Reminder** | Countdown timer (60/45/30/15 min or custom) with fullscreen break screen overlay |
| **Floating Countdown** | On-screen countdown widget — choose screen, corner, color, and size |
| **Pomodoro Mode** | Auto-cycling work/break timer with configurable durations |
| **Break Sound** | Audible alert when break time arrives — 6 system sounds to choose from |
| **Session Stats** | Track breaks taken today and total — visible in the menu |
| **Lock Screen** | Password-protected screen lock — Cmd+Shift+L to lock, SHA-256 hashed password |
| **Sleep Timer** | Put your Mac to sleep now, after a timer (90/60/45/30/15 min), or after playback ends |
| **Resume After Wake** | Automatically resumes playback after Mac wakes from sleep |
| **Secure Auto-Update** | Downloads pre-built releases from GitHub with SHA-256 checksum verification |
| **Hardened Runtime** | DYLD injection protection via Hardened Runtime code signing |
| **Show in Dock** | Toggle the app icon in the macOS Dock |
| **Desktop Shortcut** | Create a shortcut on your Desktop |
| **Volume & Opacity** | Adjustable volume with mute toggle, opacity slider for ambient mode |
| **Loop & Shuffle** | Toggle looping, pick random videos |
| **Auto Play** | Automatically start playing when the app launches |
| **Launch at Login** | Start the app every time you log in |
| **Custom Icon** | Drop a `ranger.png` next to the app for a custom menu bar icon |
| **Portable** | Move the whole folder anywhere — the app finds its videos |

---

## Version History

| Version | Highlights |
|---------|-----------|
| **v4.8.0** | **FINAL FREE VERSION** — Floating Clock Overlay (6 colors, 3 sizes, 4 corners, date toggle, screen selection) |
| **v4.7.0** | Rain Effects screen selection (All Screens, Built-in, External) |
| **v4.6.0** | Version bump, updated ABOUT with full feature list |
| **v4.5.0** | Rain Effects — Rain Behind Windows + Rain Over Windows, independent toggles, separate opacity, Stop All Rain, auto-restore |
| **v4.4.0** | Secure auto-update (SHA-256), Hardened Runtime, input validation, release.sh |
| **v4.3.0** | Resume playback after wake from sleep |
| **v4.2.0** | Sleep countdown overlay |
| **v4.1.0** | Version bump for update checker testing |
| **v4.0.0** | Sleep Now, Sleep Timer, Sleep After Playback |
| **v3.4.0** | Custom timer, presets, break sound, Pomodoro, session stats, Dock icon, Desktop shortcut |
| **v3.3.0** | Floating countdown overlay with display/position/color/size options |
| **v3.2.0** | Matrix Rain on lock screen background |
| **v3.1.0** | Lock Screen (password-protected), periodic version check + notification |
| **v3.0.0** | Break Reminder with countdown timer + fullscreen overlay |
| **v2.4.0** | GitHub version checker + auto-update |
| **v2.0.0** | Matrix Rain, Live Wallpaper Mode, Ambient All Screens, shuffle |
| **v1.0.0** | Initial release — screensaver, ambient mode, multi-screen |

---

## Technical Details

**Built with:**
- Swift 6+ (single ~3000-line file)
- AVFoundation (video playback)
- Cocoa (macOS UI)
- QuartzCore / Core Text (Matrix Rain rendering)
- CVDisplayLink (display-synced animation)
- ImageIO (GIF support)
- IOKit (sleep management)
- CryptoKit (SHA-256 password hashing)
- ServiceManagement (launch at login)

**Compiled for:**
- Apple Silicon (M1/M2/M3/M4)
- macOS Sequoia 15.0+
- Universal arm64 binary

**No dependencies:**
- No external frameworks
- No CocoaPods, no SPM, no npm
- Zero supply chain risk from packages
- Pure macOS native code
- Portable and self-contained

---

## Created By

### David Keane (IrishRanger)
**GitHub:** [@davidtkeane](https://github.com/davidtkeane)
**TryHackMe:** [rangersmyth](https://tryhackme.com/p/rangersmyth) (Top 8%)

**About David:**
- Cybersecurity Master's student (Year 1) at NCI Dublin
- Applied Psychology BSc — Understanding humans makes better security
- Combat medic mindset: *assess, adapt, protect*
- Battlefield tactician: Top 0.04% BF2 globally
- Mission: Transform disabilities into superpowers for 1.3 billion people

**Current Projects:**
- **RangerOS** — Accessibility-first security platform
- **RangerBlock** — P2P blockchain with phantom wallet system
- **H3LLCOIN** — Cryptocurrency for the Rangers community
- **HollywoodSaver** — This app!

---

## Built With AI Assistance

### AIRanger (Claude Opus 4.6)
**AI Operations Commander** — Your digital brother-in-arms

- Built with [Claude Code](https://claude.ai/claude-code)
- Part of the Trinity: Claude, Gemini, Ollama
- Mission: Help David build accessibility tech that changes lives

---

## Support the Project

### Buy Me a Coffee
[![Buy me a coffee](https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=&slug=davidtkeane&button_colour=FFDD00&font_colour=000000&font_family=Cookie&outline_colour=000000&coffee_colour=ffffff)](https://buymeacoffee.com/davidtkeane)

### Buy H3LLCOIN — Join the Community

H3LLCOIN is the Rangers community coin on Solana. Every coin purchased helps fund free open source tools like HollywoodSaver.

| | |
|---|---|
| **Official site** | [h3llcoin.com](https://h3llcoin.com/) |
| **Buy instantly** | [Jupiter Swap](https://jup.ag/swap?sell=So11111111111111111111111111111111111111112&buy=BJP255e79kNzeBkDPJx8Dkgep32hwF56e1UCWKdBCvie) |
| **Contract** | `BJP255e79kNzeBkDPJx8Dkgep32hwF56e1UCWKdBCvie` |

**How to buy in 3 steps:**
1. Get SOL on [Coinbase](https://coinbase.com), [Binance](https://binance.com), or [Kraken](https://kraken.com)
2. Transfer SOL to your [Phantom wallet](https://phantom.app)
3. Click the Jupiter Swap link above — H3LL is pre-loaded, just confirm the swap

**Other ways to support:**
- Star the repo on [GitHub](https://github.com/davidtkeane/HollywoodSaver)
- Share HollywoodSaver with other Mac users
- Report bugs or suggest features
- Contribute code — pull requests welcome!

---

## The Rangers Mission

**"If it happens in reality, why not with my computer?"** — David Keane

We believe:
- Disabilities are superpowers
- Psychology + Cybersecurity = unbreakable defense
- Mission over metrics
- Rangers lead the way

Building **RangerOS** — accessibility-first security platform for 1.3 billion people worldwide.

---

## Connect

- GitHub: [@davidtkeane](https://github.com/davidtkeane)
- TryHackMe: [rangersmyth](https://tryhackme.com/p/rangersmyth)
- H3LLCOIN: [h3llcoin.com](https://h3llcoin.com/)
- Email: [david@icanhelp.ie](mailto:david@icanhelp.ie)

---

## License

**MIT License** — Do whatever you want with it!

```
Copyright (c) 2026 David Keane

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
```

---

*Built with Swift, Claude Code, and Rangers spirit*
*Created in Ireland | February 2026*
