import AppKit
import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Games

enum Game: String, CaseIterable, Identifiable {
    case bo1, bo2, bo3, boiii, waw
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bo1: "T5 - BOI"
        case .bo2: "T6 - BOII"
        case .bo3: "T7 - BOIII (Mac Version)"
        case .boiii: "T7 - BOIII (Windows Version)"
        case .waw: "T4 - WaW"
        }
    }
    var subtitle: String {
        switch self {
        case .bo1: "Plutonium · Zombies, Campaign, Multiplayer"
        case .bo2: "Plutonium · Zombies, Multiplayer"
        case .bo3: "Native Mac game · community servers"
        case .boiii: "BOIII · Ezz community servers"
        case .waw: "Coming soon"
        }
    }
    var symbol: String {
        switch self {
        case .bo1: "1.circle.fill"
        case .bo2: "2.circle.fill"
        case .bo3: "3.circle.fill"
        case .boiii: "3.square.fill"
        case .waw: "clock.fill"
        }
    }
    var colors: [Color] {
        switch self {
        case .bo1: [Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.04, green: 0.12, blue: 0.35)]
        case .bo2: [Color(red: 0.92, green: 0.18, blue: 0.20), Color(red: 0.30, green: 0.04, blue: 0.06)]
        case .bo3: [Color(red: 0.98, green: 0.52, blue: 0.10), Color(red: 0.35, green: 0.12, blue: 0.03)]
        case .boiii: [Color(red: 0.98, green: 0.52, blue: 0.10), Color(red: 0.35, green: 0.12, blue: 0.03)]
        case .waw: [Color(red: 0.55, green: 0.55, blue: 0.50), Color(red: 0.15, green: 0.15, blue: 0.13)]
        }
    }
    /// Settings key of the game folder, for the Plutonium games.
    var folderKey: String? {
        switch self {
        case .bo1: "BO1_DIR"
        case .bo2: "BO2_DIR"
        case .boiii: "BOIII_DIR"
        default: nil
        }
    }
    var usesEngine: Bool { self == .bo1 || self == .bo2 || self == .boiii }
    var usesPlutonium: Bool { self == .bo1 || self == .bo2 }
}

struct PlayMode: Identifiable {
    let id: String      // launch.sh mode
    let title: String
    let symbol: String
}

extension Game {
    var modes: [PlayMode] {
        switch self {
        case .bo1: [PlayMode(id: "online", title: "Play Online", symbol: "globe"),
                    PlayMode(id: "zombies", title: "Zombies", symbol: "figure.walk"),
                    PlayMode(id: "campaign", title: "Campaign", symbol: "flag.fill"),
                    PlayMode(id: "mp", title: "Multiplayer", symbol: "person.3.fill")]
        case .bo2: [PlayMode(id: "online", title: "Play Online", symbol: "globe"),
                    PlayMode(id: "zombies", title: "Zombies", symbol: "figure.walk"),
                    PlayMode(id: "mp", title: "Multiplayer", symbol: "person.3.fill")]
        case .boiii: [PlayMode(id: "play", title: "Play", symbol: "play.fill"),
                      PlayMode(id: "launcher", title: "BOIII Launcher", symbol: "person.2.fill")]
        default: []
        }
    }
}

// MARK: - Patches

/// A fix the launcher applies; on by default. `key` is its settings.conf
/// name (read by launch.sh), `offValue` what turns it off.
struct Patch: Identifiable {
    let key: String
    var offValue = "0"
    let title: String
    let info: String
    let games: Set<Game>
    var id: String { key }
}

extension Patch {
    static let all: [Patch] = [
        // Both games
        Patch(key: "X87", title: "x87 acceleration",
              info: "Runs the games' old x87 floating-point maths as native ARM code with athei's x87sidecar (based on Lifeisawful's rosettax87), instead of Rosetta's slow emulation. The biggest frame-rate gain.",
              games: [.bo1, .bo2]),
        Patch(key: "EXEC_ON_DEMAND", title: "Fast code execution",
              info: "Plutonium turns off DEP, so Wine would make the game's whole memory executable at once, which makes Rosetta re-check it constantly (BO2 ran in slow motion). Our engine makes each page executable only when it is first run.",
              games: [.bo1, .bo2, .boiii]),
        Patch(key: "RUMBLE_FIX", title: "Controller vibration without input delay",
              info: "Every vibration command is a round trip to the controller, and Wine made the controller's input wait for it twice: in XInput (the game waited too) and in its HID bus driver (winebus), which held the device lock during the write and so held back every stick and button report. Aiming and shooting lagged whenever the controller rumbled. Ours sends vibration from its own thread and writes it without blocking input.",
              games: [.bo1, .bo2, .boiii]),
        Patch(key: "RAW_INPUT", title: "Raw mouse input",
              info: "Reads the mouse directly, without macOS pointer acceleration or smoothing, so aim follows your hand 1:1.",
              games: [.bo1, .bo2]),
        Patch(key: "AIM_ACCEL", offValue: "1", title: "No stick turn acceleration",
              info: "Turns off the games' stick turn acceleration and sets a 0.08 stick deadzone (adjustable below), so controller aim responds immediately and evenly.",
              games: [.bo1, .bo2]),
        Patch(key: "CAPTURE_DISPLAY", title: "Direct fullscreen",
              info: "In fullscreen the game takes over the display, so macOS shows its frames directly instead of compositing them with the desktop: lower latency and steadier frame times.",
              games: [.bo1, .bo2, .boiii]),
        Patch(key: "DISPLAY_MODE", title: "Native display mode in fullscreen",
              info: "While the game runs fullscreen, the display switches to a 1x mode of the game's resolution, so a scaled (HiDPI) desktop does not make macOS draw every frame at twice the size.",
              games: [.bo1, .bo2, .boiii]),
        Patch(key: "MSAA_FIX", title: "Supported anti-aliasing",
              info: "Apple GPUs support up to 4x MSAA; higher settings in the games' configs are lowered to 4x so the game does not fall back or render wrongly.",
              games: [.bo1, .bo2]),
        // Black Ops
        Patch(key: "BO1_ASYNC", title: "Background shader compilation",
              info: "New shaders compile on separate threads instead of stopping the frame that needs them.",
              games: [.bo1]),
        Patch(key: "BO1_WARM", title: "Compile shaders while the map loads",
              info: "Our DXVK detects the game's shader-warming pass and keeps the loading screen up until every shader of the map is compiled, so the map never stutters while you play. The first visit to a map takes up to a minute longer to load; later visits take no extra time.",
              games: [.bo1]),
        Patch(key: "BO1_SHADER_CACHE", title: "Persistent shader caches",
              info: "Keeps compiled shaders between runs (DXVK's pipeline list and MoltenVK's translated shaders, in eight parallel caches) and merges pipeline lists from older setups, so maps you have played load and run without compiling again.",
              games: [.bo1]),
        Patch(key: "BO1_METAL_PARALLEL", title: "Parallel Metal compilation",
              info: "Lets Metal compile shaders on every CPU core at once instead of a few at a time.",
              games: [.bo1]),
        Patch(key: "BO1_NO_SHADOWS", title: "Shadow freeze fix",
              info: "Turns off the dynamic shadow maps, which froze Black Ops under DXVK on Apple GPUs.",
              games: [.bo1]),
        Patch(key: "STREAM", offValue: "1", title: "Load all textures up front",
              info: "Turns off texture streaming: every texture loads at full detail with the map instead of popping in (late-loading or black textures). Uses about 1.4 GB of memory.",
              games: [.bo1]),
        Patch(key: "BO1_VIDMEM", title: "Full video memory",
              info: "Black Ops reads its video memory through DirectDraw, where Wine reported 128 MB and the game capped texture quality to fit. It now sees 4 GB.",
              games: [.bo1]),
        Patch(key: "BO1_XAUDIO", title: "Gunfire sound fix",
              info: "Uses the XAudio2 from the game's own DirectX redistributable: with Wine's, Black Ops plays no gunfire sounds.",
              games: [.bo1]),
        // Black Ops II
        Patch(key: "BO2_ASYNC", title: "Background shader compilation",
              info: "DXMT compiles new Metal pipelines on separate threads instead of stopping the frame that needs them.",
              games: [.bo2, .boiii]),
        Patch(key: "BO2_FRAME_PACING", title: "Frame pacing",
              info: "DXMT paces frames evenly at the frame-rate cap (the monitor's refresh rate by default) instead of letting them bunch up.",
              games: [.bo2, .boiii]),
        Patch(key: "BO2_HW_PROFILE", title: "Safe hardware profile",
              info: "Starts Black Ops II with a blank hardware profile so it detects settings Apple GPUs support (otherwise it can pick 8x MSAA, which they do not have).",
              games: [.bo2]),
        // Black Ops III (Windows)
        Patch(key: "BOIII_GRAPHICS", title: "Full-detail first start",
              info: "On its first start Black Ops III's auto-detect does not know Apple GPUs and picks half resolution with no shadows. Instead it starts fullscreen at your display's size and refresh rate with full resolution, shadows, volumetric lighting, ambient occlusion and SMAA. Only once: the game's own options rule afterwards.",
              games: [.boiii]),
    ]

    static func `for`(_ game: Game) -> [Patch] { all.filter { $0.games.contains(game) } }
}

// MARK: - Paths

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Black Ops Mac")
    static var engine: URL { home.appendingPathComponent("engine") }
    static var prefix: URL { home.appendingPathComponent("prefix") }
    static var settings: URL { home.appendingPathComponent("settings.conf") }
    static var plutonium: URL {
        prefix.appendingPathComponent("drive_c/users/crossover/AppData/Local/Plutonium")
    }
    /// The kit (scripts and engine payload): in the app bundle, or the one
    /// BOM_KIT points at while developing.
    static var kit: URL {
        if let dev = ProcessInfo.processInfo.environment["BOM_KIT"] { return URL(fileURLWithPath: dev) }
        return Bundle.main.resourceURL!.appendingPathComponent("kit")
    }
    /// Wine prefixes with Plutonium from older setups, offered for import
    /// (the Plutonium login and game settings come with them), most recently
    /// played first.
    static var importCandidates: [URL] {
        let fm = FileManager.default
        var found: [URL] = []
        func isCandidate(_ url: URL) -> Bool {
            fm.fileExists(atPath: url.appendingPathComponent("system.reg").path)
                && fm.fileExists(atPath: url.appendingPathComponent("drive_c/users/crossover/AppData/Local/Plutonium/bin").path)
        }
        let home = fm.homeDirectoryForCurrentUser
        for root in ["Downloads", "Documents", "Desktop", "Games"] {
            guard let items = fm.enumerator(at: home.appendingPathComponent(root), includingPropertiesForKeys: nil,
                                            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            while let url = items.nextObject() as? URL {
                if items.level > 6 { items.skipDescendants(); continue }
                if url.lastPathComponent == "drive_c" || url.lastPathComponent == "node_modules" { items.skipDescendants(); continue }
                if isCandidate(url) { found.append(url); items.skipDescendants() }
            }
        }
        // CrossOver bottles
        let bottles = home.appendingPathComponent("Library/Application Support/CrossOver/Bottles")
        for b in (try? fm.contentsOfDirectory(at: bottles, includingPropertiesForKeys: nil)) ?? [] where isCandidate(b) {
            found.append(b)
        }
        func lastPlayed(_ url: URL) -> Date {
            let storage = url.appendingPathComponent("drive_c/users/crossover/AppData/Local/Plutonium/storage")
            return ((try? fm.attributesOfItem(atPath: storage.path))?[.modificationDate] as? Date) ?? .distantPast
        }
        return found.sorted { lastPlayed($0) > lastPlayed($1) }
    }
}

// MARK: - Settings (settings.conf, read by launch.sh)

struct Settings {
    var values: [String: String] = [:]

    static func load() -> Settings {
        var s = Settings()
        guard let text = try? String(contentsOf: Paths.settings, encoding: .utf8) else { return s }
        for line in text.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard !l.hasPrefix("#"), let eq = l.firstIndex(of: "=") else { continue }
            s.values[String(l[..<eq])] = String(l[l.index(after: eq)...])
        }
        return s
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.home, withIntermediateDirectories: true)
        let body = values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: "\n")
        try? ("# BO-Mac settings (written by the app)\n" + body + "\n")
            .write(to: Paths.settings, atomically: true, encoding: .utf8)
    }

    subscript(key: String) -> String? {
        get { values[key] }
        set { values[key] = (newValue?.isEmpty ?? true) ? nil : newValue }
    }
}

// MARK: - App state

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var settings = Settings.load()
    @Published var log: [String] = []
    @Published var progress: String?          // a running setup step
    @Published var running: Game?             // a game started from here
    @Published var error: String?
    @Published var bo3Latest: String?
    @Published var bo3: [String: String] = [:]   // bo3.sh status: game, state, installed
    @Published var zd: [String: String] = [:]    // zombies-declassified.sh status: installed, latest
    @Published var settingsGame: Game?           // the settings panel shown over the window
    @Published var x87Latest: String?
    @Published var refreshToken = 0           // bumped to re-read statuses

    private var task: Process?

    init() {
        // A game left running from an earlier session of the app
        if Self.engineRunning {
            running = settings["LAST_GAME"].flatMap(Game.init(rawValue:)) ?? .bo1
            watchUntilStopped()
        }
    }

    // Statuses
    var engineInstalled: Bool {
        FileManager.default.fileExists(atPath: Paths.engine.appendingPathComponent("black-ops-mac.version").path)
    }
    var engineInfo: [String: String] {
        guard let t = try? String(contentsOf: Paths.engine.appendingPathComponent("black-ops-mac.version"), encoding: .utf8) else { return [:] }
        var d: [String: String] = [:]
        for l in t.split(separator: "\n") { let p = l.split(separator: "=", maxSplits: 1); if p.count == 2 { d[String(p[0])] = String(p[1]) } }
        return d
    }
    var prefixReady: Bool {
        FileManager.default.fileExists(atPath: Paths.prefix.appendingPathComponent("system.reg").path)
    }
    var plutoniumInstalled: Bool {
        FileManager.default.fileExists(atPath: Paths.plutonium.appendingPathComponent("bin/plutonium-launcher-win32.exe").path)
    }
    var crossOverVersion: String? {
        let plist = URL(fileURLWithPath: "/Applications/CrossOver.app/Contents/Info.plist")
        guard let d = NSDictionary(contentsOf: plist) else { return nil }
        return d["CFBundleShortVersionString"] as? String
    }
    var rosettaInstalled: Bool { FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime") }
    func folder(for game: Game) -> URL? {
        guard let key = game.folderKey, let path = settings[key] else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("zone").path) ? url : nil
    }
    var steamInstalled: Bool { FileManager.default.fileExists(atPath: "/Applications/Steam.app") }
    /// "ready", "downloading" (in Steam) or "missing"
    var bo3GameState: String { bo3["state"] ?? "missing" }
    var bo3Installed: Bool { !(bo3["installed"] ?? "").isEmpty }
    var bo3Version: String? { bo3Installed ? bo3["installed"] : nil }
    /// boiii.exe in the Windows Black Ops III folder
    var boiiiInstalled: Bool {
        guard let f = folder(for: .boiii) else { return false }
        return FileManager.default.fileExists(atPath: f.appendingPathComponent("boiii.exe").path)
    }
    func downloadBoiii() { runScript("boiii.sh", ["download"], title: "Downloading boiii.exe") }

    /// BOIII stats, loadouts and identity keys, saved in one zip / put back.
    func backupBoiii() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        panel.message = "Choose where to save your BOIII backup (stats, loadouts and identity). Keep it private."
        panel.prompt = "Save Backup"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runScript("boiii.sh", ["backup", url.path], title: "Backing up your BOIII stats")
    }

    func restoreBoiii() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.zip]
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        panel.message = "Choose a BOIII backup. Your current stats and identity go to the Trash."
        panel.prompt = "Restore"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runScript("boiii.sh", ["restore", url.path], title: "Restoring your BOIII stats")
    }
    func createEmptyPrefix() { runScript("setup-prefix.sh", ["init"], title: "Creating the Wine prefix") }

    func isReady(_ game: Game) -> Bool {
        switch game {
        case .bo1, .bo2: engineInstalled && prefixReady && plutoniumInstalled && folder(for: game) != nil
        case .boiii: engineInstalled && prefixReady && folder(for: game) != nil && boiiiInstalled
        case .bo3: bo3Installed
        case .waw: false
        }
    }

    // MARK: Actions

    func chooseFolder(for game: Game) {
        guard let key = game.folderKey else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        panel.message = game == .boiii
            ? "Choose the Windows Black Ops III folder (the one with BlackOps3.exe and the zone folder)"
            : "Choose the \(game.title) folder (the one with the zone folder inside)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("zone").path) else {
            error = "That folder has no zone folder: pick the \(game.title) game folder."
            return
        }
        settings[key] = url.path
        settings.save()
        refreshToken += 1
    }

    func installEngine() { runScript("install-engine.sh", [], title: "Installing the engine") }
    func updateX87() { runScript("install-engine.sh", ["--update-x87"], title: "Updating the x87 accelerator") }
    func importPrefix(_ url: URL) { runScript("setup-prefix.sh", ["import", url.path], title: "Importing your Plutonium setup") }
    func createPrefix(gameFolder: URL) { runScript("setup-prefix.sh", ["create", gameFolder.path], title: "Setting up Plutonium") }
    func installBO3() {
        runScript("bo3.sh", ["install"], title: "Installing BO3 Mac Client") { [weak self] in self?.refreshBO3() }
    }
    func openBO3() { runScript("bo3.sh", ["open"], title: nil) }
    func playBO3OnSteam() { runScript("bo3.sh", ["steam"], title: nil) }

    // Zombies Declassified (Black Ops II mod)
    var zdInstalled: String? { (zd["installed"] ?? "").isEmpty ? nil : zd["installed"] }
    var zdLatest: String? { (zd["latest"] ?? "").isEmpty ? nil : zd["latest"] }
    func zombiesDeclassified(_ action: String) {
        let titles = ["install": "Installing Zombies Declassified", "verify": "Checking Zombies Declassified",
                      "remove": "Removing Zombies Declassified"]
        runScript("zombies-declassified.sh", [action], title: titles[action]) { [weak self] in self?.refreshZD() }
    }
    func refreshZD() {
        Task.detached {
            var d: [String: String] = [:]
            for line in Self.capture("zombies-declassified.sh", ["status"]).split(separator: "\n") {
                let p = line.split(separator: "=", maxSplits: 1)
                d[String(p[0])] = p.count == 2 ? String(p[1]) : ""
            }
            let status = d
            await MainActor.run { self.zd = status }
        }
    }

    /// uninstall.sh: "bo1", "bo2", "all" (engine and Plutonium too) or "bo3".
    func removeSetup(_ what: String) {
        let titles = ["bo1": "Removing the Black Ops setup", "bo2": "Removing the Black Ops II setup",
                      "all": "Removing the engine and Plutonium", "bo3": "Removing BO3 Mac Client"]
        running = nil
        runScript("uninstall.sh", [what], title: titles[what] ?? "Removing") { [weak self] in
            guard let self else { return }
            self.settings = Settings.load()
            self.refreshBO3()
        }
    }

    /// BO3MacFix's ranked spoofing: opt-in (see BO3View for the risks).
    var bo3SpoofRanked: Bool { settings["BO3_SPOOF_RANKED"] == "1" }
    func setBO3SpoofRanked(_ on: Bool) {
        settings["BO3_SPOOF_RANKED"] = on ? "1" : "0"
        settings.save()
        runScript("bo3.sh", ["spoof", on ? "on" : "off"], title: nil) { [weak self] in self?.refreshBO3() }
    }

    func refreshBO3() {
        Task.detached {
            var d: [String: String] = [:]
            for line in Self.capture("bo3.sh", ["status"]).split(separator: "\n") {
                let p = line.split(separator: "=", maxSplits: 1)
                d[String(p[0])] = p.count == 2 ? String(p[1]) : ""
            }
            let status = d
            await MainActor.run {
                self.bo3 = status
                self.bo3Latest = status["latest"].flatMap { $0.isEmpty ? nil : $0 }
            }
        }
    }

    func play(_ game: Game, mode: PlayMode) {
        // The games open the microphone (voice chat); Wine then waits for
        // macOS's answer. Ask here, once, so the question shows over this
        // window instead of behind the game's fullscreen loading screen.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in self.play(game, mode: mode) }
            }
            return
        }
        running = game
        settings["LAST_GAME"] = game.rawValue
        settings.save()
        let name = settings["PLAYER_NAME"] ?? "Player"
        runScript("launch.sh", [game.rawValue, mode.id, name], title: nil) { [weak self] in
            // The Plutonium launcher may exit while the game it started
            // keeps running: the game is over when the engine's Wine is.
            self?.watchUntilStopped()
        }
    }

    func stop() {
        task?.terminate()
        runScript("launch.sh", ["stop"], title: nil)
        running = nil
    }

    /// Wine processes running from our engine.
    nonisolated static var engineRunning: Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", Paths.engine.path + "/"]
        p.standardOutput = Pipe()
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private func watchUntilStopped() {
        Task.detached {
            while Self.engineRunning { try? await Task.sleep(for: .seconds(2)) }
            await MainActor.run { self.running = nil }
        }
    }

    // MARK: App updates (GitHub releases of the repository)

    nonisolated static let repository = "sirdankdabs/bo-mac"
    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    var kitVersion: String? {
        (try? String(contentsOf: Paths.kit.appendingPathComponent("VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct Release: Sendable { let version: String; let notes: String; let download: URL }

    /// On launch (quietly) or from the menu (says so when up to date): offers
    /// the newer release, never installs on its own.
    func checkForAppUpdate(manual: Bool) {
        let current = appVersion
        Task.detached {
            let release = Self.latestRelease()
            await MainActor.run {
                guard let release else {
                    if manual { self.error = "Couldn't check for updates. Check your internet connection and try again." }
                    return
                }
                if Self.isNewer(release.version, than: current) {
                    self.offerUpdate(release)
                } else if manual {
                    let alert = NSAlert()
                    alert.messageText = "You're up to date"
                    alert.informativeText = "BO-Mac \(current) is the latest version."
                    alert.runModal()
                }
            }
        }
    }

    private func offerUpdate(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "BO-Mac \(release.version) is available"
        var notes = release.notes.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "### ", with: "")
        if notes.count > 900 { notes = String(notes.prefix(900)) + "…" }
        alert.informativeText = "You have \(appVersion).\n\n\(notes)"
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { installUpdate(release) }
    }

    nonisolated static func latestRelease() -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let zip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
              let link = zip["browser_download_url"] as? String, let download = URL(string: link) else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, notes: json["body"] as? String ?? "", download: download)
    }

    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Downloads the release, puts it in place of this app (the old one goes
    /// to the Trash) and opens it.
    private func installUpdate(_ release: Release) {
        guard running == nil else { error = "Quit the game first, then update."; return }
        progress = "Downloading BO-Mac \(release.version)"
        let current = Bundle.main.bundleURL
        Task.detached {
            do {
                let (file, _) = try await URLSession.shared.download(from: release.download)
                let fm = FileManager.default
                let dir = fm.temporaryDirectory.appendingPathComponent("bom-update-\(UUID().uuidString)")
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-x", "-k", file.path, dir.path]
                try unzip.run(); unzip.waitUntilExit()
                guard let app = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                        .first(where: { $0.pathExtension == "app" }) else { throw CocoaError(.fileReadCorruptFile) }
                try fm.trashItem(at: current, resultingItemURL: nil)
                try fm.moveItem(at: app, to: current)
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                relaunch.arguments = ["-c", "sleep 1; xattr -dr com.apple.quarantine \"$0\" 2>/dev/null; open \"$0\"", current.path]
                try relaunch.run()
                await MainActor.run { NSApp.terminate(nil) }
            } catch {
                await MainActor.run {
                    self.progress = nil
                    self.error = "The update could not be installed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// After an update: the files this app installs (engine modules, BO3 Mac
    /// Client) are replaced with the ones it now carries. Settings, Plutonium
    /// and shader caches are kept.
    func refreshInstalledFiles() {
        guard running == nil, progress == nil else { return }
        if engineInstalled, let kit = kitVersion, engineInfo["kit"] != kit {
            runScript("install-engine.sh", [], title: "Updating the game files") { [weak self] in self?.refreshBO3Files() }
        } else {
            refreshBO3Files()
        }
    }

    private func refreshBO3Files() {
        Task.detached {
            var status: [String: String] = [:]
            for line in Self.capture("bo3.sh", ["status"]).split(separator: "\n") {
                let p = line.split(separator: "=", maxSplits: 1)
                status[String(p[0])] = p.count == 2 ? String(p[1]) : ""
            }
            let installed = status["installed"] ?? "", bundled = status["latest"] ?? ""
            let current = status, ready = status["state"] == "ready"
            await MainActor.run {
                self.bo3 = current
                if !installed.isEmpty, !bundled.isEmpty, installed != bundled, ready {
                    self.runScript("bo3.sh", ["install"], title: "Updating BO3 Mac Client", env: ["NO_OPEN": "1"]) {
                        self.refreshBO3()
                    }
                }
            }
        }
    }

    func checkUpdates() {
        refreshBO3()
        refreshZD()
        Task.detached {
            let x87 = Self.latestX87()
            await MainActor.run { self.x87Latest = x87 }
        }
    }

    nonisolated static func latestX87() -> String? {
        guard let url = URL(string: "https://api.github.com/repos/athei/x87sidecar/releases/latest"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["tag_name"] as? String
    }

    nonisolated static func capture(_ script: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [Paths.kit.appendingPathComponent(script).path] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// Run a kit script, streaming its output to the log; "==> " lines show
    /// as the current step, "ERROR: " lines as an alert.
    func runScript(_ script: String, _ args: [String], title: String?, env: [String: String] = [:],
                   done: (() -> Void)? = nil) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [Paths.kit.appendingPathComponent(script).path] + args
        if !env.isEmpty { p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 } }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        if let title { progress = title; log.append("— \(title)") }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                guard let self else { return }
                for line in text.split(separator: "\n") {
                    let l = String(line)
                    self.log.append(l)
                    if l.hasPrefix("==> ") { self.progress = String(l.dropFirst(4)) }
                    if l.hasPrefix("ERROR: ") { self.error = String(l.dropFirst(7)) }
                }
                if self.log.count > 2000 { self.log.removeFirst(self.log.count - 2000) }
            }
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                if title != nil { self?.progress = nil }
                self?.refreshToken += 1
                done?()
            }
        }
        do {
            try p.run()
            if title == nil || script == "launch.sh" { task = p }
        } catch {
            self.error = "Cannot run \(script): \(error.localizedDescription)"
            progress = nil
        }
    }
}
