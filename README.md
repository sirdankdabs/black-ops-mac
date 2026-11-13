# BO-Mac

**Call of Duty: Black Ops, Black Ops II and Black Ops III (Mac and Windows versions) on Apple silicon Macs — in one app.**

Choose your game folder, press Install, press Play. No CrossOver, no Wine to install, no `.command` files, no Terminal.

[**Download the app**](https://github.com/sirdankdabs/bo-mac/releases/latest) · [What it does](#what-it-does) · [Requirements](#requirements) · [Credits](#credits)

## What it does

### T5 – BOI · Black Ops (Plutonium)

- **Online through Plutonium and offline** — Zombies, Campaign and Multiplayer, with every patch below applied in both.
- **~160 FPS on an M1 Pro**, held steady: worst frames around 10–15 ms instead of constant stutter.
- **No shader stutter.** Our DXVK detects the game's shader-warming pass and keeps the loading screen up until every shader of the map is compiled — on all CPU cores at once. A list of ~19,000 pipelines gathered on every zombies map ships with the app, so even the first shot and first explosion are already compiled. The first visit to a map takes up to a minute longer to load; after that, it loads instantly.
- **Persistent shader caches** (DXVK's pipeline list and MoltenVK's translated shaders in eight parallel caches), saved in the background on the efficiency cores.
- **No black or late textures**: full 4 GB of video memory (Wine reported 128 MB), textures loaded up front, fixes for Apple GPUs.
- **Gunfire sound fixed** (the game's own XAudio2), **shadow freeze fixed**.
- **Your settings from the start**: fullscreen at your display's resolution, sync every frame, automatic texture quality, 16x anisotropic filtering, shader warming on.

### T6 – BOII · Black Ops II (Plutonium)

- **Online through Plutonium and offline** — Zombies and Multiplayer.
- **160 FPS on an M1 Pro** (capped at the display's refresh rate) instead of ~86 FPS in slow motion: Direct3D 11 runs on Metal through DXMT, with background pipeline compilation and frame pacing.
- **Starts fullscreen at 1920×1080** with anti-aliasing Apple GPUs support (it otherwise opened in a small 800×600 window).
- **Zombies Declassified** built in — Black Ops II's unreleased "DLC 5" (Nacht der Untoten, Verrückt, Shi No Numa, Der Riese, Kino der Toten, "Five", Ascension, Shangri-La, Moon): one-click install with the mod's own verified installer, a **Declassified** play button, file check and remove.

### T6 – BOII (Campaign) · Black Ops II's campaign from Steam

- **The campaign of your Steam copy** (`t6sp.exe`; Plutonium has no campaign), with the same Direct3D 11 → Metal setup as Black Ops II: DXMT, background pipelines, frame pacing, x87 acceleration, controller fixes.
- **Your game folder can be anywhere**: choose it (downloaded with the Mac Steam app, copied from a PC, on an external drive…). BO-Mac shows it to Steam through a library of its own.
- **Windows Steam in its own Wine prefix** (the game's Steam DRM needs it), separate from every other game; its in-game overlay is off. The first time you press **Play Campaign**, Steam opens to sign in and the game starts once you have; after that, Steam starts in the background and signs in by itself.
- **Starts fullscreen at 1920×1080** (an Apple-GPU hardware profile, once), with a 1x display mode while the game runs.

### T7 – BOIII (Mac Version) · Black Ops III from Steam

- **Play on Steam *and* on the community servers with the same install.** BO3MacFix (with the T7Patch 3.09 security and gameplay fixes, audio and stutter fixes) goes into your Steam copy of the game: **Play on Steam** starts it for Steam's own matchmaking, and **Community Servers** opens the server browser for the BOIII/Ezz dedicated servers — the same servers Windows players join.
- **T7 Server Browser**: every community server with map, mode, round, players and ping; search and filters; type your player name and press Join — it starts the game through Steam and connects you.
- **Password-protected servers**: Join or double-click a locked server and type its password.
- **Workshop custom maps and mods**: servers running a custom map or a mod download it from the Workshop when you join.
- **Controllers in Switch mode** (Nintendo Switch Pro and pads like GameSir's) are recognised: the game's own controller list didn't include them.
- **Joins busy servers** (the client finds the server id Windows servers never send to the Mac, also on long-running servers) and **skips the intro cutscene** as soon as the map has loaded.
- **Ranked spoofing (optional, off by default)**, with its risks stated: it changes your real Steam stats and can get your account banned.
- Everything is included in the app (source in `bo3/`): nothing is downloaded from anywhere else.

### T7 – BOIII (Windows Version) · Black Ops III for Windows through boiii

- **The Windows game on the BOIII / Ezz community client** ([boiii.exe](https://github.com/Ezz-lol/boiii-free), downloaded from its latest release and checked against its published SHA-256), on our engine with DXMT (Direct3D 11 → Metal).
- **boiii's launcher works** (friends, player name, Workshop, settings): it is Internet Explorer's browser control, whose HTML document class Wine prefixes made for Plutonium didn't register — so it was a blank white window.
- **No Steam needed**: the game refuses to start without Steam installed; the app registers an empty Steam folder whose `steam.exe` does nothing, so boiii plays without Steam or a Steam login.
- **Windows Media Feature Pack check passed**: the engine now has Media Foundation's video decoders (Wine's winegstreamer with GStreamer and Apple's VideoToolbox hardware decoder).
- **Renders correctly on Metal**: a DXMT fix for the game's upscaling pass (it binds a render target larger than its depth buffer; DXMT dropped those draws and the screen stayed black).
- **Full detail from the first start**: the game's auto-detect doesn't know Apple GPUs and picks half resolution with no shadows; instead it starts fullscreen at your display's size and refresh rate, 100% resolution, shadows, volumetric lighting, ambient occlusion and SMAA (once — the game's own options rule afterwards).
- **Fullscreen at 1x**: the display switches to a 1x mode of its size while the game runs, so the picture fills the screen on HiDPI displays.
- **No Safe Mode prompt** after the game is stopped from the app.
- **Back up your stats**: *Back Up Stats…* saves your stats, loadouts, save games and the identity keys the servers know you by in one zip — keep it, take it to another Mac (*Restore Stats…*) or to Windows.
- Known issue: pre-rendered cutscene videos show wrong colours (purple/green); the game itself is unaffected.

### For every game

- **Our own engine, built entirely from open source** — Wine 11 from CodeWeavers' published CrossOver 26.3 source, with patches written for Plutonium under Rosetta 2:
  - *Hardware breakpoint emulation*: Rosetta cannot deliver x86 debug-register breakpoints, which Plutonium needs to start; the engine turns them into software breakpoints with trampolines, hidden from Plutonium's own integrity checks.
  - *Execution on demand*: Plutonium turns off DEP, which made Wine mark the whole game executable at once and Rosetta re-check it constantly (BO2 ran in slow motion). Pages are now made executable when they are first run.
  - *x87 acceleration*: hand-off to athei's **x87sidecar**, which runs the games' x87 floating-point maths as native ARM code.
- **Controllers, with vibration and without input lag** — Wine waited for every rumble write twice (in XInput and in its HID bus driver, which held the controller's lock during a Bluetooth/USB round trip), and games change vibration almost every frame while firing: vibration now goes out on its own, at most 25 times a second, so it never holds up the controller's input.
- **Raw mouse input, no stick acceleration, 0.08 deadzone, direct fullscreen at native resolution, macOS Game Mode.**
- **Voice chat**: the app asks for microphone access once, so games never hang waiting for macOS's answer.
- **Every patch can be switched off** in each game's settings, with an ⓘ explaining what it does.
- **Plutonium's folder picker** opens with shortcuts to your Mac home, Downloads, Documents and the game folders.
- **Remove setup** for each game, to start again from scratch (everything goes to the Trash; your games are never touched).
- **Updates**: the app tells you when a new version is out (and *BO-Mac → Check for Updates…*); after updating it refreshes the files it installed, keeping your settings, Plutonium login and shader caches.
- **No macOS accent menu** when holding a movement key in the games.

## Requirements

- A Mac with Apple silicon, macOS 14 or later, and Rosetta 2.
- Nothing else: no CrossOver, no Wine to install. The app downloads our engine, built entirely from open source (see *The engine* below).
- Your own copies of the games:
  - Black Ops / Black Ops II folders with `plutonium.exe` inside (from [plutonium.pw](https://plutonium.pw)), and a Plutonium account to play online.
  - Black Ops III from Steam (the Mac version), and/or the Windows version of Black Ops III (the game folder with `BlackOps3.exe`).

## Use it

1. Download `BO-Mac.app` from the [latest release](https://github.com/sirdankdabs/bo-mac/releases/latest) (or build it: `./build-app.sh`, requires the Xcode command line tools). The first time, right-click it → **Open** (it is not notarized).

2. **Prepare your game folder:** Make sure your game files are in a single folder containing `plutonium.exe`. This is the folder you must select during installation when prompted to choose the game directory.

3. Open the app and pick a game:
   - **Black Ops / Black Ops II**: *Install* the engine → *Choose…* the game folder containing `plutonium.exe` → *Install* Plutonium (sign in when its window opens) or *Import* an older Wine prefix. After you sign in, close the Plutonium window, then select **Play Online** (Plutonium launcher), **Zombies**, **Campaign**, or **Multiplayer** (offline/LAN) directly from the app.
   - **Black Ops III**: Once the game is installed through Steam, click *Install* → the server browser will open. From there, select any server you want to join, and the game will launch automatically. Once the game opens, navigate to the corresponding game mode (e.g., Zombies), and you'll automatically join the selected server. Alternatively, you can launch the game directly through Steam to join Steam servers or open the server browser separately to connect to community servers.

   - **T6 – BOII (Campaign)**: *Install* Steam for Windows → *Choose…* your game folder (wherever it is) → **Play Campaign**. The first time, Steam opens to sign in (the window may stay black: click it, type your user name, Tab, password, Enter; approve Steam Guard on your phone).
   - **Black Ops III (Windows Version)** — see below.

4. The first time you load a Black Ops map, the loading screen will remain visible while all shaders are compiled (up to about a minute). Subsequent loads will be much faster.

## Playing the Windows version of Black Ops III

1. Get the **Windows** version of Black Ops III onto your Mac: a folder with `BlackOps3.exe`, `zone/` and `video/` inside (for example, copy it from a Windows PC, or download it with Steam on Windows). Keep it anywhere, e.g. `~/Games/Black Ops III`.
2. Open BO-Mac and choose **T7 – BOIII (Windows Version)**.
3. Follow the checklist, top to bottom:
   - **Engine** → *Install* (shared with the other games; skip if it's already there).
   - **Game folder** → *Choose…* the folder with `BlackOps3.exe`.
   - **Wine prefix** → *Create* (skip if you already play Black Ops / Black Ops II here).
   - **boiii.exe** → *Download* (the latest BOIII / Ezz client, verified, put into the game folder).
4. Press **Open BOIII**: boiii's own launcher opens — set your player name, add friends, browse the Workshop, then press its **PLAY**. (**Play Directly** skips the launcher.) The first start takes a little longer while shaders compile; the game opens fullscreen with full detail.
5. In the game, pick **Zombies** or **Multiplayer** and use boiii's **server browser** to join community servers, or play solo / with bots.
6. **Settings** (white button): every fix can be switched off, with an ⓘ for each.
7. **Back Up Stats…** now and then: your stats live in the game folder and your identity in the Wine prefix — the backup has both. On Windows, put `boiii_players` next to `boiii.exe` and the `key` files in `%LOCALAPPDATA%\boiii\user`.

**Play Directly** uses the player name from the app's **Settings**.

## The engine

Built entirely from open source by `engine/build-engine.sh`, and published in this repository's releases:

- **Wine** — CodeWeavers' published CrossOver 26.3 source code (LGPL), with our patches (`kit/patches`), compiled for Apple silicon (x86_64 under Rosetta 2, 32- and 64-bit Windows programs).
- **macOS libraries** Wine loads (FreeType, GnuTLS and its dependencies, SDL2, libinotify) — x86_64 builds from [Sikarugir](https://github.com/Sikarugir-App)'s wrapper template.
- **Wine Mono** from WineHQ, for Plutonium's installer, and **Wine Gecko** from WineHQ, which draws boiii's launcher.
- **winegstreamer** with **GStreamer 1.24** (LGPL, CrossOver 26's x86_64 build) and its plugins, for Media Foundation video decoding.
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
  boiii.sh             boiii.exe download (verified) and stats backup / restore
  bo2-campaign.sh      BO2 campaign: Windows Steam in its own prefix, library, sign-in wait
  zombies-declassified.sh   the BO2 mod (via its own verified installer)
  uninstall.sh         remove a game's setup (to the Trash)
  prepare-shaders.sh   optional: compile every BO1 map ahead of time
  patches/             source of every change to Wine, DXVK and DXMT
  payload/             built modules (d3d9.dll, winebus.sys, xinput1_3.dll, DXMT, MoltenVK shim),
                       BO1's pipeline list, BO2's hardware profile, BO3 Mac Client
  tools/               mvkcache.c (MoltenVK cache), statecache-merge.py, displaymode, gamemode-plist.py
engine/              build-engine.sh / pack-engine.sh: the engine from source
bo3/                 BO3 Mac Client source (SwiftUI browser + client engine) and BO3MacFix source (LGPL-2.1)
build-app.sh         builds dist/BO-Mac.app
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
- **Ezz / BOIII** — [boiii-free](https://github.com/Ezz-lol/boiii-free), the community client for the Windows version (downloaded from its latest release), built on momo5502's BOIII.
- **GStreamer** contributors.

Not affiliated with Activision, Treyarch, Aspyr, Valve, CodeWeavers or Plutonium. Call of Duty and Black Ops are trademarks of Activision Publishing, Inc. You need your own copies of the games.

## License

The app and scripts: MIT. The patches follow the licenses of what they patch (Wine: LGPL-2.1+, DXVK: zlib, DXMT: its license). Downloaded components keep their own licenses.
