# Black Ops Mac

**Call of Duty: Black Ops, Black Ops II and Black Ops III on Apple silicon Macs — in one app.**

Black Ops and Black Ops II run through [Plutonium](https://plutonium.pw) (online and offline) on our own Wine engine, built from CrossOver's open-source Wine with patches written for these games. Black Ops III runs natively from Steam, on the community dedicated servers, through BO3 Mac Client. World at War is next.

No `.command` files, no Terminal: choose your game folder, press Install, press Play.

## What it achieves

Measured on a MacBook Pro M1 Pro (1080p, 160 Hz display):

| | Before | With Black Ops Mac |
| --- | --- | --- |
| Black Ops (Kino der Toten) | stutters, black textures, minutes of "Shader Warming" | **~160 FPS**, worst frames 10–15 ms, no shader compiling mid-game |
| Black Ops II (Nuketown Zombies) | ~86 FPS, slow motion | **160 FPS** (capped at the display rate) |
| First load of a new BO1 map | shader warming for minutes, then stutter | about a minute, once; then instant |
| Controller with vibration | input lag on every shot | no lag |

Highlights:

- **Our own engine** — Wine 11 (CrossOver 26.3 source) with patches made for Plutonium under Rosetta 2:
  - *Hardware breakpoint emulation*: Rosetta cannot deliver x86 debug-register breakpoints, which Plutonium needs; the engine turns them into software breakpoints with trampolines, hiding them from Plutonium's own integrity checks.
  - *Execution on demand*: Plutonium disables DEP, which made Wine mark the whole game executable at once and Rosetta re-check it constantly (BO2 ran in slow motion). Pages are now made executable only when first run.
  - *x87 acceleration*: cooperative hand-off to athei's **x87sidecar**, which runs the games' x87 floating-point maths as native ARM code.
- **Black Ops on DXVK + MoltenVK, tuned for Apple GPUs**
  - Our DXVK detects the game's shader-warming pass, compiles every pipeline of the map in parallel and keeps the loading screen up until they are done: the map never stutters while you play.
  - A persistent, **sharded MoltenVK pipeline cache** (8 caches, picked by shader hash) — MoltenVK locks a cache while compiling, so one shared cache meant one Metal compile at a time. Now all cores compile.
  - Fixes for Apple GPUs (optional geometry shaders/cull distance, separate depth-sampler slots), full video memory (4 GB instead of 128 MB), working gunfire audio (native XAudio2), shadow freeze fix, textures loaded up front.
- **Black Ops II on DXMT** (D3D11 → Metal) with asynchronous pipeline compilation and frame pacing.
- **Controller vibration without input lag** — Wine waited for each rumble write twice (XInput and the HID bus driver held the controller's lock during a Bluetooth/USB round trip). Both are fixed.
- **Raw mouse input, no stick acceleration, 0.08 deadzone, native-resolution fullscreen, Game Mode.**
- **Your settings from the start**: fullscreen at the display's resolution, sync every frame, automatic texture quality, 16x anisotropic filtering, shader warming (BO1); a Black Ops II hardware profile made on an Apple GPU so it starts fullscreen instead of in a small window.
- **Plutonium's folder picker** opens with shortcuts to your Mac home, Downloads, Documents and the game folders.
- **Every patch can be switched off** in each game's settings, with an ⓘ explaining what it does.
- **Zombies Declassified** (Black Ops II's unreleased "DLC 5": BO1 and World at War zombies maps in BO2) — one-click install, verify, remove and play.
- **Black Ops III**: installs BO3 Mac Client into your Steam game and opens its server browser (renamed *T7 Server Browser*): pick a community server, type your name, Join. Ranked spoofing is opt-in, with its risks stated.
- **Remove setup** for each game (everything goes to the Trash; your games are never touched).

## Requirements

- A Mac with Apple silicon, macOS 14 or later, and Rosetta 2.
- Nothing else: no CrossOver, no Wine to install. The app downloads our engine, built entirely from open source (see *The engine* below).
- Your own copies of the games:
  - Black Ops / Black Ops II folders with `plutonium.exe` inside (from [plutonium.pw](https://plutonium.pw)), and a Plutonium account to play online.
  - Black Ops III from Steam (the Mac version).

## Use it

1. Build the app (`./build-app.sh`, needs the Xcode command line tools) or take `Black Ops Mac.app` from a release.
2. Open it, pick a game:
   - **Black Ops / Black Ops II**: *Install* the engine → *Choose…* the game folder → *Install* Plutonium (sign in when its window opens) or *Import* an older Wine prefix. Then **Play Online** (Plutonium launcher), **Zombies**, **Campaign** or **Multiplayer** (offline/LAN).
   - **Black Ops III**: when Steam has the game, *Install* → the server browser opens.
3. The first time you visit a Black Ops map, its loading screen stays up while every shader is compiled (up to about a minute). After that, it loads straight away.

## The engine

Built entirely from open source by `engine/build-engine.sh`, and published in this repository's releases:

- **Wine** — CodeWeavers' published CrossOver 26.3 source code (LGPL), with our patches (`kit/patches`), compiled for Apple silicon (x86_64 under Rosetta 2, 32- and 64-bit Windows programs).
- **macOS libraries** Wine loads (FreeType, GnuTLS and its dependencies, SDL2, libinotify) — x86_64 builds from [Sikarugir](https://github.com/Sikarugir-App)'s wrapper template.
- **Wine Mono** from WineHQ, for Plutonium's installer.
- Completed at install time with our DXVK, DXMT, MoltenVK (Khronos) and athei's x87sidecar.

No CrossOver installation, licence or trial is involved. (If the engine release cannot be downloaded, the installer falls back to CrossOver 26.3's runtime.)

## How it is put together

```
app/                 SwiftUI app (BlackOpsMac)
kit/                 what the app runs (also usable from Terminal)
  install-engine.sh    builds the engine from CrossOver's runtime + our modules
  setup-prefix.sh      Wine prefix + Plutonium (install or import)
  launch.sh            starts a game with every patch (settings.conf switches)
  bo3.sh               BO3 Mac Client install / open / Steam / ranked spoofing
  zombies-declassified.sh   the BO2 mod (via its own verified installer)
  uninstall.sh         remove a game's setup (to the Trash)
  prepare-shaders.sh   optional: compile every BO1 map ahead of time
  patches/             source of every change to Wine, DXVK and DXMT
  payload/             the built modules (ntdll.so, winebus.sys, xinput1_3.dll, d3d9.dll, DXMT, MoltenVK shim)
  tools/               mvkcache.c (MoltenVK cache), statecache-merge.py, displaymode, gamemode-plist.py
build-app.sh         builds dist/Black Ops Mac.app
```

## Credits

- **Plutonium** team — the Black Ops / Black Ops II clients.
- **CodeWeavers** — CrossOver and its published open-source Wine; **the Wine project**; **WineHQ** — Wine Mono.
- **Sikarugir** (Gcenx and contributors) — the wrapper template whose x86_64 libraries the engine uses.
- **Lifeisawful** — [rosettax87](https://github.com/Lifeisawful/rosettax87), the original x87 acceleration for Rosetta; **athei** — [x87sidecar](https://github.com/athei/x87sidecar), the accelerator used here (downloaded from its latest release).
- **DXVK** by Philip Rebohle and contributors; **Sporif** — the dxvk-async patch; **3Shain** — [DXMT](https://github.com/3Shain/dxmt).
- **Khronos / MoltenVK** contributors.
- **Logo-2K** — [Zombies Declassified](https://github.com/Logo-2K/zombies-declassified).
- **BO3 Mac Client** ([sirdankdabs/BO3-Mac-Client](https://github.com/sirdankdabs/BO3-Mac-Client)), built on **BO3MacFix** by Emma / InvoxiPlayGames and Anthony / serious, with **T7Patch** work by its authors; the community server project behind `master.ezz.lol`.

Not affiliated with Activision, Treyarch, Aspyr, Valve, CodeWeavers or Plutonium. Call of Duty and Black Ops are trademarks of Activision Publishing, Inc. You need your own copies of the games.

## License

The app and scripts: MIT. The patches follow the licenses of what they patch (Wine: LGPL-2.1+, DXVK: zlib, DXMT: its license). Downloaded components keep their own licenses.
