# Wyrm macOS

First engine bring-up for OM Rajput. Universal native application for Intel
and Apple Silicon, targeting macOS 12 Monterey and later. Uses the exact C
engine compiled by Wyrm Desktop, SDL3 and Vulkan through MoltenVK.

Public source: https://github.com/disis-om/wyrm-macos. Cloud builds use standard
hosted Mac runners; no paid larger runners or signing services are configured.

## Development download — 0.1.0 (1)

[Download the universal test artifact](https://github.com/disis-om/wyrm-macos/actions/runs/39463554764/artifacts/12283773018)
(sign in to download; retained for 30 days). Inside the artifact, extract
`Wyrm-macOS-universal.zip` to get `Wyrm.app`.

[Build and native checks](https://github.com/disis-om/wyrm-macos/actions/runs/39463554764),
source `01fb58d0e18800d0667dcea25f14a5aacb7af573`: universal compile, actual
macOS 12 minimum metadata, bundled dependencies and ad-hoc signatures verified.
The packaged app ran offline AI for 120 presented frames and exited cleanly
on both hosted Intel and Apple Silicon Macs. Online arena entry, minimum-OS
runtime, physical input/visual review and T480s gameplay remain unverified.

ZIP SHA-256:
`94855fce838e16f62b56c2aa7af07dabddbe9355144b11ccf09c12d002a53517`.

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
