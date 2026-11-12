# Black Ops Mac

**Call of Duty: Black Ops, Black Ops II and Black Ops III on Apple silicon Macs — in one app.**

Choose your game folder, press Install, press Play. No CrossOver, no Wine to install, no `.command` files, no Terminal.

[**Download the app**](https://github.com/sirdankdabs/t7-mac/releases/latest) · [What it does](#what-it-does) · [Requirements](#requirements) · [Credits](#credits)

## What it does

### Black Ops (Plutonium T5)

- **Online through Plutonium and offline** — Zombies, Campaign and Multiplayer, with every patch below applied in both.
- **~160 FPS on an M1 Pro**, held steady: worst frames around 10–15 ms instead of constant stutter.
- **No shader stutter.** Our DXVK detects the game's shader-warming pass and keeps the loading screen up until every shader of the map is compiled — on all CPU cores at once. A list of ~19,000 pipelines gathered on every zombies map ships with the app, so even the first shot and first explosion are already compiled. The first visit to a map takes up to a minute longer to load; after that, it loads instantly.
- **Persistent shader caches** (DXVK's pipeline list and MoltenVK's translated shaders in eight parallel caches), saved in the background on the efficiency cores.
- **No black or late textures**: full 4 GB of video memory (Wine reported 128 MB), textures loaded up front, fixes for Apple GPUs.
- **Gunfire sound fixed** (the game's own XAudio2), **shadow freeze fixed**.
- **Your settings from the start**: fullscreen at your display's resolution, sync every frame, automatic texture quality, 16x anisotropic filtering, shader warming on.

### Black Ops II (Plutonium T6)

- **Online through Plutonium and offline** — Zombies and Multiplayer.
- **160 FPS on an M1 Pro** (capped at the display's refresh rate) instead of ~86 FPS in slow motion: Direct3D 11 runs on Metal through DXMT, with background pipeline compilation and frame pacing.
- **Starts fullscreen at 1920×1080** with anti-aliasing Apple GPUs support (it otherwise opened in a small 800×600 window).
- **Zombies Declassified** built in — Black Ops II's unreleased "DLC 5" (Nacht der Untoten, Verrückt, Shi No Numa, Der Riese, Kino der Toten, "Five", Ascension, Shangri-La, Moon): one-click install with the mod's own verified installer, a **Declassified** play button, file check and remove.

### Black Ops III (Steam, native Mac version)

- **Play on Steam *and* on the community servers with the same install.** BO3MacFix (with the T7Patch 3.09 security and gameplay fixes, audio and stutter fixes) goes into your Steam copy of the game: **Play on Steam** starts it for Steam's own matchmaking, and **Community Servers** opens the server browser for the BOIII/Ezz dedicated servers — the same servers Windows players join.
- **T7 Server Browser**: every community server with map, mode, round, players and ping; search and filters; type your player name and press Join — it starts the game through Steam and connects you.
- **Password-protected servers**: Join or double-click a locked server and type its password.
- **Joins busy servers** (the client finds the server id Windows servers never send to the Mac, also on long-running servers) and **skips the intro cutscene** as soon as the map has loaded.
- **Ranked spoofing (optional, off by default)**, with its risks stated: it changes your real Steam stats and can get your account banned.
- Everything is included in the app (source in `bo3/`): nothing is downloaded from anywhere else.

### For every game

- **Our own engine, built entirely from open source** — Wine 11 from CodeWeavers' published CrossOver 26.3 source, with patches written for Plutonium under Rosetta 2:
  - *Hardware breakpoint emulation*: Rosetta cannot deliver x86 debug-register breakpoints, which Plutonium needs to start; the engine turns them into software breakpoints with trampolines, hidden from Plutonium's own integrity checks.
  - *Execution on demand*: Plutonium turns off DEP, which made Wine mark the whole game executable at once and Rosetta re-check it constantly (BO2 ran in slow motion). Pages are now made executable when they are first run.
  - *x87 acceleration*: hand-off to athei's **x87sidecar**, which runs the games' x87 floating-point maths as native ARM code.
- **Controllers, with vibration and without input lag** — Wine waited for every rumble write twice (in XInput and in its HID bus driver, which held the controller's lock during a Bluetooth/USB round trip). Both are fixed.
- **Raw mouse input, no stick acceleration, 0.08 deadzone, direct fullscreen at native resolution, macOS Game Mode.**
- **Voice chat**: the app asks for microphone access once, so games never hang waiting for macOS's answer.
- **Every patch can be switched off** in each game's settings, with an ⓘ explaining what it does.
- **Plutonium's folder picker** opens with shortcuts to your Mac home, Downloads, Documents and the game folders.
- **Remove setup** for each game, to start again from scratch (everything goes to the Trash; your games are never touched).

## Requirements

- A Mac with Apple silicon, macOS 14 or later, and Rosetta 2.
- Nothing else: no CrossOver, no Wine to install. The app downloads our engine, built entirely from open source (see *The engine* below).
- Your own copies of the games:
  - Black Ops / Black Ops II folders with `plutonium.exe` inside (from [plutonium.pw](https://plutonium.pw)), and a Plutonium account to play online.
  - Black Ops III from Steam (the Mac version).

## Use it

1. Download `Black Ops Mac.app` from the [latest release](https://github.com/sirdankdabs/t7-mac/releases/latest) (or build it: `./build-app.sh`, needs the Xcode command line tools). The first time, right-click it → **Open** (it is not notarized).
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
  install-engine.sh    installs the engine (our release) + our modules
  setup-prefix.sh      Wine prefix + Plutonium (install or import)
  launch.sh            starts a game with every patch (settings.conf switches)
  bo3.sh               BO3 Mac Client install / open / Steam / ranked spoofing
  zombies-declassified.sh   the BO2 mod (via its own verified installer)
  uninstall.sh         remove a game's setup (to the Trash)
  prepare-shaders.sh   optional: compile every BO1 map ahead of time
  patches/             source of every change to Wine, DXVK and DXMT
  payload/             built modules (d3d9.dll, winebus.sys, xinput1_3.dll, DXMT, MoltenVK shim),
                       BO1's pipeline list, BO2's hardware profile, BO3 Mac Client
  tools/               mvkcache.c (MoltenVK cache), statecache-merge.py, displaymode, gamemode-plist.py
engine/              build-engine.sh / pack-engine.sh: the engine from source
bo3/                 BO3 Mac Client source (SwiftUI browser + client engine) and BO3MacFix source (LGPL-2.1)
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
- **BO3 Mac Client** (included in `bo3/` and `kit/payload/bo3`), built on **BO3MacFix** by Emma / InvoxiPlayGames and Anthony / serious, with **T7Patch** work by its authors; the community server project behind `master.ezz.lol`.

Not affiliated with Activision, Treyarch, Aspyr, Valve, CodeWeavers or Plutonium. Call of Duty and Black Ops are trademarks of Activision Publishing, Inc. You need your own copies of the games.

## License

The app and scripts: MIT. The patches follow the licenses of what they patch (Wine: LGPL-2.1+, DXVK: zlib, DXMT: its license). Downloaded components keep their own licenses.
