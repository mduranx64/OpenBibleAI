# OpenBibleAI

## Building

Open `OpenBibleAI.xcodeproj` in Xcode and build. Simulator builds work out of the
box with no configuration.

To build and run on a device, you need to supply your own signing identity. The
project reads it from an untracked xcconfig file, so nothing about your Apple
Developer account ends up in a commit:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Then edit `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM` to your 10-character
Apple Developer Team ID and `BUNDLE_ID_PREFIX` to a reverse-DNS prefix you
control. `Config/Shared.xcconfig` picks the file up automatically, so no Xcode
settings need changing.
