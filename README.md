# Wyrm macOS

First engine bring-up for OM Rajput. Universal native application for Intel
and Apple Silicon, targeting macOS 12 Monterey and later. Uses the exact C
engine compiled by Wyrm Desktop, SDL3 and Vulkan through MoltenVK.

This prototype provides a live arena directory, custom endpoint, player name,
Play and offline AI. Mouse steers; click/Space boosts, P toggles assist,
Q leaves, F11 toggles fullscreen. Home/Play again remain available after death.
Account, social, cloud settings and the full Desktop shell are later stages.
All prototype settings are session-only; nothing uploads to an account.

On a Mac with Xcode command-line tools, CMake, Python 3 and a JDK (headers only):

```sh
bash Scripts/fetch-dependencies.sh
python3 Scripts/prepare-engine.py
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release '-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64'
cmake --build build --parallel 3
bash Scripts/package.sh
```

The JDK is a build dependency only. The delivered app does not require Java,
a Vulkan SDK, SDL or Homebrew. The CI workflow creates `Wyrm-macOS-universal.zip`
and a SHA-256 file. Extract, move Wyrm.app to Applications, then open it. This
development build is ad-hoc signed, not notarized. If macOS blocks it, use
System Settings > Privacy & Security > Open Anyway for this app.

Intel hardware needs working Metal acceleration (including on a Hackintosh).
Compilation does not prove graphics drivers, joining or sustained play on a
physical Mac. Logs: `~/Library/Logs/Wyrm/engine.log`.

Engine provenance is recorded in `SharedEngine/SHA256.json`. Refresh only from
the live workspace engine, never from an old Android Git commit. GPL licensing
and bundled component notices are retained.
