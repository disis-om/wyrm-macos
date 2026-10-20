# Wyrm macOS architecture

## Engine authority

Desktop compiles the live Wyrm Android app/src and thermite tree. SharedEngine
transports those exact files to standalone macOS CI, with SHA-256 verification
before adaptation. Original gameplay, networking, AI, shaders and renderer stay
intact. Generated/ is disposable, and all adaptation anchors fail closed.

## Host

SDL3 owns the visible, resizable window and main-thread event loop. The original
Vulkan renderer presents directly through MoltenVK; Windows CPU readback is
disabled. Portability extensions are enabled when advertised, using the proven
iOS Apple Vulkan adapter. Desktop mouse/keyboard semantics stay selected.
The macOS launcher draws with the engine's existing Dear ImGui and packaged
Wyrm fonts: restrained paper/ink composition, green Play accent, no web view.
Play posts into the engine's bounded home mailbox. No game objects cross threads.

The first-stage adapter leaves the original JNI-exported entrypoints compiled
against JDK headers but uncalled. Platform publication getters return NULL;
there is no JVM, Java host, libjvm dependency or Activity at runtime. The narrow
macOS API accesses the existing mailbox within its translation unit. Startup
failures display a native alert. Death/retry/leave route through engine commands.

## Assets and state

Bundle Resources contains app/res. The process starts from Resources so original
relative paths remain valid. Engine user.dat/temp/backup paths resolve to a
fresh session temp directory, removed at exit; no persistent setting bypasses
the account registry. Launcher name and arena are also session-only. Account
save/restore and macos/shared document integration are explicitly pending.
The live directory uses the same rolling nibble decoder and record layouts as
Android, bounded to 128 KiB, 2048 rows. No game-port probing or packet changes.

## Build and delivery

Pinned, hash-checked SDL3 3.4.16 and MoltenVK 1.4.2 Apple frameworks. CMake builds
a universal macOS 12 app; CI validates both Mach-O slices, dependent frameworks,
bundle layout and ad-hoc signatures, then uploads a zipped development artifact.
An offline-only `--smoke-ai` check opens the actual engine, dismisses the practice
notice through an SDL Enter event, and requires 120 presented AI frames, snakes
and no network socket. Hosted graphics failures are retained as separate evidence;
they do not turn a successful compile into a false gameplay claim.
No Apple signing secrets or backend credentials are required. CI is build proof;
Intel and Apple Silicon physical gameplay are separate pending verification.
