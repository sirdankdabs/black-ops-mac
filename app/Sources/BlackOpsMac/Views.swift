import SwiftUI

@main
struct BlackOpsMacApp: App {
    // The app itself doesn't observe the state: if it did, every change (a log
    // line, a status refresh) would rebuild the whole scene and the menu bar,
    // which made the menus stutter. The window's view observes it instead.
    var body: some Scene {
        WindowGroup("BO-Mac") {
            RootView()
                .frame(minWidth: 1080, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { AppState.shared.checkForAppUpdate(manual: true) }
            }
        }
    }
}

struct RootView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        ContentView()
            .environmentObject(state)
            .onAppear {
                state.checkUpdates()
                state.refreshInstalledFiles()
                state.checkForAppUpdate(manual: false)
            }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    // `-openSettings bo1` on the command line opens that game's settings
    @State private var selection: Game = UserDefaults.standard.string(forKey: "openSettings")
        .flatMap(Game.init(rawValue:)) ?? .bo2
    @State private var showLog = false

    var body: some View {
        NavigationSplitView {
            List(Game.allCases, selection: $selection) { game in
                GameRow(game: game, selected: game == selection).tag(game)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 240, ideal: 250, max: 320)
            .safeAreaInset(edge: .bottom) { EngineFooter(showLog: $showLog) }
        } detail: {
            GameDetail(game: selection)
                .id("\(selection.rawValue)-\(state.refreshToken)")
        }
        .sheet(isPresented: $showLog) { LogView() }
        .overlay {
            if let g = state.settingsGame {
                ZStack {
                    // clicking outside the panel closes it without saving
                    Color.black.opacity(0.4).ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { state.settingsGame = nil }
                    SettingsView(game: g) { state.settingsGame = nil }
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 30)
                        .onExitCommand { state.settingsGame = nil }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: state.settingsGame)
        .onChange(of: selection) { state.settingsGame = nil; if selection == .bo2c { state.startCampaignSteam() } }
        .onAppear { if selection == .bo2c { state.startCampaignSteam() } }
        .alert("Something went wrong", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("OK") { state.error = nil }
            Button("Show log") { state.error = nil; showLog = true }
        } message: {
            Text(state.error ?? "")
        }
    }
}

struct GameRow: View {
    @EnvironmentObject var state: AppState
    let game: Game
    var selected = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: game.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 34, height: 34)
                .overlay(Image(systemName: game.symbol).foregroundStyle(.white).font(.system(size: 16, weight: .bold)))
            VStack(alignment: .leading, spacing: 2) {
                Text(game.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(selected ? Color.white : game.colors[0])
                Text(statusText).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(game == .waw ? 0.55 : 1)
    }

    private var statusText: String {
        if game == .waw { return "Coming soon" }
        if state.running == game { return "Running" }
        return state.isReady(game) ? "Ready" : "Set up"
    }
}

// MARK: - Detail

struct GameDetail: View {
    @EnvironmentObject var state: AppState
    let game: Game

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [game.colors[0].opacity(0.85), game.colors[1], .black],
                           startPoint: .topLeading, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Spacer().frame(height: 18)
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.title.uppercased())
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .kerning(1.5)
                    Text(game.subtitle).font(.system(size: 14, weight: .medium)).opacity(0.8)
                }
                .foregroundStyle(.white)

                switch game {
                case .bo1, .bo2, .bo2c, .boiii: PlutoniumGameView(game: game)
                case .bo3: BO3View()
                case .waw: ComingSoonView()
                }
                Spacer()
                if let p = state.progress {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text(p).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(32)
        }
        .onAppear {
            if game.usesEngine, UserDefaults.standard.string(forKey: "openSettings") == game.rawValue {
                UserDefaults.standard.removeObject(forKey: "openSettings")
                state.settingsGame = game
            }
        }
    }
}

struct PlutoniumGameView: View {
    @EnvironmentObject var state: AppState
    let game: Game
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
            if game == .bo2 && state.isReady(game) { DeclassifiedCard() }
            if state.folder(for: game) != nil || state.engineInstalled {
                Button { confirmRemove = true } label: {
                    Label("Remove setup…", systemImage: "trash").font(.system(size: 11, weight: .medium))
                }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.75))
                    .disabled(state.progress != nil)
            }
        }
        .confirmationDialog("Remove the \(game.title) setup?", isPresented: $confirmRemove) {
            Button("Remove the \(game.title) setup", role: .destructive) { state.removeSetup(game.rawValue) }
            Button("Remove everything (engine and Plutonium)", role: .destructive) { state.removeSetup("all") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(game == .bo2c
                 ? "Campaign setup: moves its own Wine prefix with Steam for Windows (and your sign-in there) to the Trash and forgets the game folder. The game files stay.\n\nEverything: also moves the engine and the Plutonium prefix to the Trash."
                 : game == .boiii
                 ? "Black Ops III (Windows) setup: forgets the game folder. The game, boiii.exe and your stats in it are not touched.\n\nEverything: also moves the engine and the Wine prefix (Plutonium, its login and BOIII's identity keys: back up your stats first) to the Trash."
                 : game == .bo1
                 ? "Black Ops setup: forgets the game folder and moves its shader caches to the Trash (the next visit to each map compiles again).\n\nEverything: also moves the engine and the Wine prefix with Plutonium (and its login) to the Trash, so Black Ops and Black Ops II are both set up again from the start.\n\nYour game folders are not touched."
                 : "Black Ops II setup: forgets the game folder and its mod arguments.\n\nEverything: also moves the engine and the Wine prefix with Plutonium (and its login) to the Trash, so Black Ops and Black Ops II are both set up again from the start.\n\nYour game folders are not touched.")
        }
    }

    private var modes: [PlayMode] {
        var m = game.modes
        if game == .bo2, state.zdInstalled != nil {
            m.append(PlayMode(id: "declassified", title: "Declassified", symbol: "moon.stars.fill"))
        }
        return m
    }

    @ViewBuilder private var content: some View {
        if state.isReady(game) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ForEach(modes) { mode in
                        BigButton(title: mode.title, symbol: mode.symbol, primary: mode.id == "online" || mode.id == "launcher") {
                            state.play(game, mode: mode)
                        }
                        .disabled(state.running != nil || state.progress != nil)
                    }
                    BigButton(title: "Settings", symbol: "slider.horizontal.3", outlined: true) { state.settingsGame = game }
                        .help("Settings and patches")
                }
                if state.running == game {
                    Button { state.stop() } label: { Label("Stop the game", systemImage: "stop.fill") }
                        .buttonStyle(.bordered).tint(.white)
                }
                if game == .boiii {
                    HStack(spacing: 10) {
                        Button { state.backupBoiii() } label: { Label("Back Up Stats…", systemImage: "externaldrive.badge.plus") }
                        Button { state.restoreBoiii() } label: { Label("Restore Stats…", systemImage: "arrow.counterclockwise") }
                        InfoButton(text: "BOIII keeps your stats, loadouts and save games in the game folder (boiii_players) and the identity the servers know you by in Wine's AppData. Back Up saves both in one zip you can keep, take to another Mac (Restore) or to Windows (boiii_players goes next to boiii.exe, the key files in %LOCALAPPDATA%\\boiii\\user). Keep the zip private: anyone with it can play as you.")
                    }
                    .buttonStyle(.bordered).tint(.white)
                    .disabled(state.running != nil || state.progress != nil)
                }
            }
        } else {
            SetupChecklist(game: game)
        }
    }
}

struct DeclassifiedCard: View {
    @EnvironmentObject var state: AppState
    @State private var confirmInstall = false
    @State private var confirmRemove = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "moon.stars.fill").font(.system(size: 22)).foregroundStyle(.white).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Zombies Declassified").font(.system(size: 14, weight: .bold))
                    InfoButton(text: "Zombies Declassified by Logo-2K (github.com/Logo-2K/zombies-declassified) is Black Ops II's unreleased \"DLC 5\": Nacht der Untoten, Verrückt, Shi No Numa, Der Riese, Kino der Toten, \"Five\", Ascension, Shangri-La and Moon, ported to Black Ops II as a Plutonium mod. It needs the full game with all DLC.\n\nInstalled with the mod's own installer: every file is checked against the release's SHA-256, and any game file it replaces is backed up.\n\nOffline: the Declassified button. Online: in the game, Mods → dlc5.")
                }
                Text(statusText).font(.system(size: 11)).opacity(0.75)
            }
            .foregroundStyle(.white)
            Spacer()
            HStack(spacing: 8) {
                if state.zdInstalled == nil {
                    Button("Install…") { confirmInstall = true }
                } else {
                    if let l = state.zdLatest, l != state.zdInstalled { Button("Update to \(l)…") { confirmInstall = true } }
                    Button("Check files") { state.zombiesDeclassified("verify") }
                    Button("Remove…") { confirmRemove = true }
                }
            }
            .disabled(state.progress != nil || state.running != nil)
        }
        .padding(14)
        .frame(maxWidth: 620, alignment: .leading)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
        .confirmationDialog("Install Zombies Declassified?", isPresented: $confirmInstall) {
            Button("Install") { state.zombiesDeclassified("install") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downloads about 9 GB from the mod's GitHub release (stopped downloads resume where they left off) into Black Ops II's sound folder and Plutonium's mods folder.")
        }
        .confirmationDialog("Remove Zombies Declassified?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { state.zombiesDeclassified("remove") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Moves the mod's files to the Trash and puts back any game file it had replaced.")
        }
        .task { state.refreshZD() }
    }

    private var statusText: String {
        if let v = state.zdInstalled { return "Installed (\(v)): BO1 and World at War zombies maps in Black Ops II" }
        return "BO1 and World at War zombies maps in Black Ops II · about 9 GB"
    }
}

struct SetupChecklist: View {
    @EnvironmentObject var state: AppState
    let game: Game
    @State private var candidates: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set up").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            Check(done: state.rosettaInstalled, title: "Rosetta 2",
                  detail: "Run in Terminal: softwareupdate --install-rosetta --agree-to-license")
            Check(done: state.engineInstalled, title: "BO-Mac engine",
                  detail: "Downloads our engine, built from open source, and adds our patches. About 330 MB.") {
                Button("Install") { state.installEngine() }.disabled(state.progress != nil)
            }
            Check(done: state.folder(for: game) != nil, title: "\(game.title) game folder",
                  detail: game == .boiii ? "The Windows game's folder, with BlackOps3.exe and zone/ inside."
                        : game == .bo2c ? "Your Steam copy's folder, with t6sp.exe inside (e.g. Steam/steamapps/common/Call of Duty Black Ops II). Downloaded with the Mac Steam app is fine."
                        : "The folder with zone/ and plutonium.exe inside.") {
                Button("Choose…") { state.chooseFolder(for: game) }
            }
            if game == .bo2c {
                Check(done: state.campaignSteam["steam"] == "installed", title: "Steam for Windows (campaign only)",
                      detail: "The campaign's Steam DRM needs the Steam client. Installs Valve's Steam for Windows in the campaign's own Wine prefix (the other games are not touched).") {
                    Button("Install") { state.setupCampaignSteam() }
                        .disabled(!state.engineInstalled || state.progress != nil)
                }
                Check(done: state.campaignSteam["signedin"] == "yes", title: "Sign in to Steam",
                      detail: "Once. Steam's window may stay black: click it, type your user name, press Tab, your password, Enter (approve Steam Guard on your phone). It remembers you after that.") {
                    Button("Open Steam") { state.openCampaignSteam() }
                        .disabled(state.campaignSteam["steam"] != "installed" || state.progress != nil)
                }
            } else if game == .boiii {
                Check(done: state.prefixReady, title: "Wine prefix",
                      detail: "Where Windows programs keep their settings (shared with Black Ops and Black Ops II).") {
                    Button("Create") { state.createEmptyPrefix() }
                        .disabled(!state.engineInstalled || state.progress != nil)
                }
                Check(done: state.boiiiInstalled, title: "boiii.exe (BOIII / Ezz client)",
                      detail: "The community client for the Windows game, from github.com/Ezz-lol/boiii-free (checked against its SHA-256), into the game folder.") {
                    Button("Download") { state.downloadBoiii() }
                        .disabled(state.folder(for: game) == nil || state.progress != nil)
                }
            } else {
            Check(done: state.prefixReady && state.plutoniumInstalled, title: "Plutonium",
                  detail: candidates.isEmpty
                      ? "Installs Plutonium: sign in when its window opens, then close it."
                      : "Found an older setup: importing it keeps your Plutonium login and game settings.") {
                HStack {
                    if candidates.count == 1, let c = candidates.first {
                        Button("Import") { state.importPrefix(c) }.disabled(!state.engineInstalled || state.progress != nil)
                            .help(c.path)
                    } else if candidates.count > 1 {
                        Menu("Import") {
                            ForEach(candidates, id: \.self) { c in
                                Button(c.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) { state.importPrefix(c) }
                            }
                        }
                        .fixedSize()
                        .disabled(!state.engineInstalled || state.progress != nil)
                    }
                    Button("Install") {
                        if let f = state.folder(for: game) { state.createPrefix(gameFolder: f) }
                    }
                    .disabled(!state.engineInstalled || state.folder(for: game) == nil || state.progress != nil)
                }
            }
            }
        }
        .padding(20)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .task {
            if !state.prefixReady { candidates = await Task.detached { Paths.importCandidates }.value }
        }
    }
}

struct Check<Accessory: View>: View {
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder var accessory: () -> Accessory

    init(done: Bool, title: String, detail: String, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.done = done; self.title = title; self.detail = detail; self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .white.opacity(0.6))
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if !done { Text(detail).font(.system(size: 11)).opacity(0.7) }
            }
            .foregroundStyle(.white)
            Spacer()
            if !done { accessory() }
        }
    }
}

struct BO3View: View {
    @EnvironmentObject var state: AppState
    @State private var confirmInstall = false
    @State private var confirmSpoof = false
    @State private var confirmRemove = false

    static let spoofRisks = "Ranked spoofing (T7Patch's SPOOF_RANKED, part of BO3MacFix) makes the game treat community and modded matches as ranked, so the XP and rank you earn there count.\n\nRisks:\n• It modifies your original Steam stats for Black Ops III: your real rank, XP and stats change, also for Steam's official matchmaking, and the changes can't be undone.\n• Community servers that hand out ranks (some set you to max prestige or level 1000) then write them to your real profile too. With spoofing off, modded matches keep their stats in a separate profile that the game resets.\n• The BO3MacFix authors warn that it can get your account banned.\n\nUse it at your own risk. It is off unless you turn it on."

    private var spoofToggle: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { state.bo3SpoofRanked },
                                 set: { on in if on { confirmSpoof = true } else { state.setBO3SpoofRanked(false) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ranked spoofing (optional)").font(.system(size: 13, weight: .semibold))
                    Text("XP counts on community servers. Modifies your Steam stats; ban risk.")
                        .font(.system(size: 11)).opacity(0.75)
                }
            }
            .toggleStyle(.switch)
            InfoButton(text: Self.spoofRisks)
        }
        .foregroundStyle(.white)
        .alert("Turn on ranked spoofing?", isPresented: $confirmSpoof) {
            Button("Turn on", role: .destructive) { state.setBO3SpoofRanked(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.spoofRisks)
        }
    }

    var body: some View {
        Group {
            if state.bo3Installed { installed } else { setup }
        }
        .confirmationDialog(state.bo3Installed ? "Update BO3 Mac Client?" : "Install BO3 Mac Client?",
                            isPresented: $confirmInstall) {
            Button(state.bo3Installed ? "Update" : "Install") { state.installBO3() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Installs BO3 Mac Client, which comes with BO-Mac: BO3MacFix goes into your Black Ops III from Steam (Steam's launcher is kept as a backup), and its server browser opens when it is done.")
        }
        .task { state.refreshBO3() }
    }

    // Ready to play
    private var installed: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BigButton(title: "Community Servers", symbol: "server.rack", primary: true) { state.openBO3() }
                BigButton(title: "Play on Steam", symbol: "gamecontroller.fill") { state.playBO3OnSteam() }
                BigButton(title: updateAvailable ? "Update" : "Reinstall", symbol: "arrow.down.circle") { confirmInstall = true }
                    .disabled(state.progress != nil || state.bo3GameState != "ready")
            }
            Text(versionText).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
            spoofToggle
                .padding(12)
                .frame(maxWidth: 560, alignment: .leading)
                .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Label("Community Servers opens the server list: type your player name, pick a server and press Join. It starts the game through Steam and connects you.", systemImage: "1.circle")
                Label("Play on Steam starts Black Ops III normally, for Steam's own matchmaking. BO3MacFix's fixes apply there too.", systemImage: "2.circle")
            }
            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: 560, alignment: .leading)
            Button { confirmRemove = true } label: {
                Label("Remove BO3 Mac Client…", systemImage: "trash").font(.system(size: 11, weight: .medium))
            }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.75))
                .disabled(state.progress != nil)
                .confirmationDialog("Remove BO3 Mac Client?", isPresented: $confirmRemove) {
                    Button("Remove", role: .destructive) { state.removeSetup("bo3") }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Puts Steam's own launcher back into Black Ops III and moves BO3MacFix and the server browser to the Trash. Your identity key (rank and VIP on community servers) is kept and comes back with the next install. The game itself is not touched.")
                }
        }
    }

    // Not installed yet
    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set up").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            Check(done: state.steamInstalled, title: "Steam",
                  detail: "Install Steam from store.steampowered.com and sign in.")
            Check(done: state.bo3GameState == "ready", title: "Black Ops III (Steam version)",
                  detail: state.bo3GameState == "downloading"
                      ? "Black Ops III is still downloading in Steam. Come back when it has finished, open it once and close it."
                      : "Install Call of Duty: Black Ops III in Steam, open it once and close it.") {
                Button("Open Steam") { NSWorkspace.shared.open(URL(string: "steam://nav/games/details/311210")!) }
            }
            Check(done: false, title: "BO3 Mac Client",
                  detail: "BO3MacFix (T7Patch fixes, audio and stutter fixes, community servers) goes into the game, and the server browser opens.") {
                Button("Install") { confirmInstall = true }
                    .disabled(state.bo3GameState != "ready" || state.progress != nil)
            }
            Divider().overlay(.white.opacity(0.2))
            spoofToggle
            if let g = state.bo3["game"], !g.isEmpty {
                Text(g).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(20)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }

    private var updateAvailable: Bool {
        guard let l = state.bo3Latest, let v = state.bo3Version else { return false }
        return l != v
    }
    private var versionText: String {
        let installed = state.bo3Version ?? "not installed"
        if let l = state.bo3Latest, l != installed { return "BO3 Mac Client \(installed) · update available: \(l)" }
        return "BO3 Mac Client \(installed) · up to date"
    }
}

struct ComingSoonView: View {
    var body: some View {
        Text("World at War support is on its way.")
            .font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
    }
}

struct BigButton: View {
    let title: String
    let symbol: String
    var primary = false
    var outlined = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .bold))
            }
            .frame(width: 128, height: 84)
            .foregroundStyle(primary ? .black : .white)
            .background(primary ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.14)),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(primary ? 0 : outlined ? 0.95 : 0.25), lineWidth: outlined ? 2 : 1))
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Footer, settings, log

struct EngineFooter: View {
    @EnvironmentObject var state: AppState
    @Binding var showLog: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if state.engineInstalled {
                let info = state.engineInfo
                Text("Engine \(info["kit"] ?? "?") · \(info["base"] ?? info["crossover"].map { "CrossOver \($0)" } ?? "?")")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("x87 \(info["x87sidecar"] ?? "?")").font(.system(size: 10)).foregroundStyle(.secondary)
                    if let latest = state.x87Latest, latest != info["x87sidecar"] {
                        Button("Update to \(latest)") { state.updateX87() }
                            .font(.system(size: 10)).buttonStyle(.link)
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Show log") { showLog = true }
                Text("·").foregroundStyle(.tertiary)
                Button("Check for Updates") { state.checkForAppUpdate(manual: true) }
            }
            .font(.system(size: 10)).buttonStyle(.link)
        }
        .padding(.horizontal, 12).padding(.bottom, 10)
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    let game: Game
    var close: () -> Void
    @State private var fps = "monitor"
    @State private var patches: [String: Bool] = [:]
    @State private var deadzone = 0.08
    @State private var name = "Player"
    @State private var mods = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(game.title) settings").font(.system(size: 15, weight: .bold))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close without saving")
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
            form
        }
        .frame(width: 540, height: 560)
        .onAppear(perform: load)
    }

    private var form: some View {
        Form {
            if let folder = state.folder(for: game) {
                Section("Game folder") {
                    HStack {
                        Text(folder.path).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    }
                }
            }
            Section("Play") {
                TextField("Player name (offline)", text: $name)
                Picker("Frame-rate cap", selection: $fps) {
                    Text("Monitor's refresh rate").tag("monitor")
                    Text("240").tag("240"); Text("160").tag("160"); Text("120").tag("120")
                    Text("80").tag("80"); Text("60").tag("60"); Text("No cap").tag("0")
                }
            }
            Section {
                ForEach(Patch.for(game)) { patch in
                    HStack(spacing: 6) {
                        Toggle(patch.title, isOn: Binding(get: { patches[patch.key] ?? true },
                                                         set: { patches[patch.key] = $0 }))
                        InfoButton(text: patch.info)
                    }
                }
            } header: {
                HStack {
                    Text("Patches")
                    Spacer()
                    Button("Turn all on") { for p in Patch.for(game) { patches[p.key] = true } }
                        .buttonStyle(.link).font(.system(size: 11))
                }
            } footer: {
                Text("All patches are on by default. Changes apply the next time the game starts.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Controller") {
                HStack {
                    Text("Stick deadzone")
                    Slider(value: $deadzone, in: 0.02...0.25, step: 0.01)
                    Text(String(format: "%.2f", deadzone)).monospacedDigit().frame(width: 36)
                }
            }
            if game == .bo2 {
                Section("Mods (offline)") {
                    TextField("Extra arguments, e.g. +set fs_game mods/dlc5", text: $mods)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: close)
                Button("Save") { save(); close() }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func load() {
        let s = state.settings
        fps = s["MAXFPS"] ?? "monitor"
        for p in Patch.for(game) { patches[p.key] = s[p.key] != p.offValue }
        deadzone = Double(s["STICK_DEADZONE"] ?? "") ?? 0.08
        name = s["PLAYER_NAME"] ?? "Player"
        mods = s["BO2_MODS"] ?? ""
    }

    private func save() {
        state.settings["MAXFPS"] = fps == "monitor" ? nil : fps
        for p in Patch.for(game) { state.settings[p.key] = (patches[p.key] ?? true) ? nil : p.offValue }
        state.settings["STICK_DEADZONE"] = String(format: "%.2f", deadzone)
        state.settings["PLAYER_NAME"] = name
        state.settings["BO2_MODS"] = mods
        state.settings.save()
    }
}

struct InfoButton: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $shown, arrowEdge: .trailing) {
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(12)
        }
    }
}

struct LogView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(state.log.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("end")
                }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            }
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding()
        .frame(width: 700, height: 440)
    }
}
