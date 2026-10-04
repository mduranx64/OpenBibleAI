# OpenBibleAI

A SwiftUI Bible reader for iPhone, iPad and Mac with installable Bible versions and an on-device AI study assistant. Download the versions you want on first launch, read full chapters, compare versions verse by verse, jump to a reference such as `John 3:16`, search the text, and ask questions in a Bible chat whose answers cite verses you can open. The app reopens the last book and chapter you read. The interface is available in English, Spanish and Brazilian Portuguese.

- **iPhone:** Read, Chat, Search and Library tabs. Read goes from books to chapters to the reader; tapping a verse offers "Ask about" it in the chat, and citations in answers open the reader.
- **iPad:** a sidebar (search, books, chapters) beside the reader, with the chat in a side panel you can show or hide. In narrow Split View it uses the iPhone tabs.
- **Mac:** books, reader and chat in three columns, with keyboard shortcuts (⌘[ / ⌘] for chapters, ⌥↑ / ⌥↓ for verses).

Development is verified on **macOS with Xcode 27 and Swift 6.4**. The iPhone and iPad layouts are tested in the simulator (UI tests and screenshots); real devices are not yet checked. The app targets iOS 17, macOS 14 and visionOS 1 (visionOS uses the Mac layout).

## Start here

- [Agent instructions](AGENTS.md) — how coding agents should work in this repository.
- [Project checkpoint](MEMORY.md) — completed work, test evidence, and known gaps.
- [Roadmap](ROADMAP.md) — completed milestones and what is next.
- [Development guide](DEVELOPMENT.md) — architecture, setup, testing, on-device AI, localization, Bible versions (provenance, licensing, building and publishing packages).

## Building and testing

After cloning, run `Tools/generate_build_settings.sh` once: it writes the gitignored `OpenBibleAI/Generated/BuildSettings.swift` from `Config/*.xcconfig` (the app's *Generate build settings* phase keeps it current, but Xcode decides what to compile before that phase first runs). Then open `OpenBibleAI.xcworkspace` in Xcode to work with the app and its three local packages. Use the `OpenBibleAI` scheme to run on My Mac, an iPhone or iPad simulator, or a device, and `AllUnitTests` for the unit-test plan. Opening `OpenBibleAI.xcodeproj` directly is also supported.

Installed Bibles can always be read offline. AI study runs entirely on the device: it uses Apple Intelligence where available (iOS/macOS/visionOS 26+, Apple Intelligence on); otherwise the app offers to download a small Qwen3 model (≈1 GB, or ≈350 MB on 4 GB iPhones) that runs with MLX on Apple silicon. Intel Macs and devices with too little memory read without AI. The Bible chat retrieves passages from the version you are reading and checks every cited verse. See the development guide for the live-validation steps.

Package test commands:

```bash
swift test --package-path Modules/BibleDomain
swift test --package-path Modules/BibleData
swift test --package-path Modules/BibleAI
```

See the development guide for app unit and UI test commands (macOS, iPhone and iPad simulators) and the manual regression checklist.

## Local signing configuration

To build and run on a device, supply your own signing identity. The project reads it from an untracked xcconfig file, so nothing about your Apple Developer account needs to enter a commit:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Edit `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM` to your 10-character Apple Developer Team ID and `BUNDLE_ID_PREFIX` to a reverse-DNS prefix you control. `Config/Shared.xcconfig` picks up the file automatically. Keep the local file untracked.

## Bible data

Bible versions are downloaded on demand from this repository's `bibles` GitHub release: 31 versions, 24 English (KJV, BSB, WEB, ASV, YLT, the Douay-Rheims and the WEB with Deuterocanon, …), 5 Spanish (Reina-Valera 1909, Español Sencillo, …) and 2 Portuguese (Bíblia Livre, Nova Bíblia Viva), each with its embedding index. They are public domain or CC BY / CC BY-SA 4.0, and each one's copyright line is shown in the app. Catholic editions list the deuterocanonical books in the Old Testament. A signed catalog lets new versions, and new revisions of installed ones (offered as Update), appear without an app update. Only the `kjv` and `rv1909` packages are versioned (`Bibles/`, as test fixtures); the others are rebuilt from recipes with `Tools/BibleImport/` (see "Adding or updating a Bible version" in [the development guide](DEVELOPMENT.md), which also has the attribution and licensing details). Import tools are development-only; downloaded source archives are ignored.
