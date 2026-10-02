# OpenBibleAI

A SwiftUI Bible reader with installable Bible versions and an on-device AI study assistant. Download the versions you want on first launch (the King James Version and the Reina-Valera 1909 today), read full chapters, compare versions side by side, jump to an exact reference such as `John 3:16`, select verses for AI study, navigate between chapters, and reopen the last selected book/chapter. The interface is available in English, Spanish and Brazilian Portuguese.

The current verified development experience is **macOS with Xcode 27 and Swift 6.4**. The project declares additional Apple platforms, but their build, device, and UI behavior have not been established by the macOS checks.

## Start here

- [Agent instructions](AGENTS.md) — how Codex should work in this repository.
- [Project checkpoint](MEMORY.md) — completed work, test evidence, and known gaps.
- [Roadmap](ROADMAP.md) — text search is next.
- [Development guide](DEVELOPMENT.md) — architecture, setup, testing, on-device AI, localization, Bible versions (provenance, licensing, building and publishing packages).

## Building and testing

Open `OpenBibleAI.xcworkspace` in Xcode to work with the app and its three local packages. Use the `OpenBibleAI` scheme to run on My Mac and `AllUnitTests` for the unit-test plan. Opening `OpenBibleAI.xcodeproj` directly is also supported.

Installed Bibles can always be read offline. AI study runs entirely on the device: it uses Apple Intelligence where available (iOS/macOS/visionOS 26+, Apple Intelligence on); otherwise the app offers to download a small Qwen3 model (≈1 GB, or ≈350 MB on 4 GB iPhones) that runs with MLX on Apple silicon. Intel Macs and devices with too little memory read without AI. See the development guide for the service address and separate live-validation steps.

Package test commands:

```bash
swift test --package-path Modules/BibleDomain
swift test --package-path Modules/BibleData
swift test --package-path Modules/BibleAI
```

See the development guide for app test commands and the manual regression checklist.

## Local signing configuration

To build and run on a device, supply your own signing identity. The project reads it from an untracked xcconfig file, so nothing about your Apple Developer account needs to enter a commit:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Edit `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM` to your 10-character Apple Developer Team ID and `BUNDLE_ID_PREFIX` to a reverse-DNS prefix you control. `Config/Shared.xcconfig` picks up the file automatically. Keep the local file untracked.

## Bible data

`Bibles/kjv/` holds the KJV package (66 books and 31,102 verses from eBible.org's `eng-kjv2006` export, plus its embedding index); every version is published as a GitHub release and pinned in the app by SHA-256. Attribution, rights notices, licensing status of other versions, source URLs and hashes are in [the development guide](DEVELOPMENT.md). Import tools are development-only; downloaded source archives are ignored.
