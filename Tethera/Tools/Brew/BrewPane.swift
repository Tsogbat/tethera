import AppKit
import SwiftUI
import TetheraKit

/// Homebrew without remembering the commands: what's outdated, what's installed, search,
/// and services. Anything that changes your system runs in a Tethera session so you see it.
@MainActor
final class BrewModel: ObservableObject {
    struct Package: Identifiable, Equatable {
        let name: String
        let installed: String
        let latest: String?
        let isCask: Bool
        var id: String { (isCask ? "cask:" : "") + name }
    }

    struct Service: Identifiable, Equatable {
        let name: String
        let status: String
        var id: String { name }
    }

    enum Tab: String, CaseIterable { case outdated = "Outdated", installed = "Installed", search = "Search", services = "Services" }

    @Published var tab: Tab = .outdated
    @Published private(set) var outdated: [Package] = []
    @Published private(set) var installed: [Package] = []
    @Published private(set) var results: [Package] = []
    @Published private(set) var services: [Service] = []
    @Published private(set) var loading = false
    @Published private(set) var missing = false
    @Published var query = ""
    private var brew: String?
    /// The session running the last brew command; the lists refresh when it finishes.
    private(set) var runningSession: UUID?

    func load() async {
        brew = await ShellEnvironment.shared.resolve("brew")
        missing = brew == nil
        guard brew != nil else { return }
        loading = true
        defer { loading = false }
        switch tab {
        case .outdated: await loadOutdated()
        case .installed: await loadInstalled()
        case .search: await search()
        case .services: await loadServices()
        }
    }

    private func run(_ arguments: [String]) async -> (ok: Bool, output: String) {
        guard let brew else { return (false, "") }
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brew)
            process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            env["HOMEBREW_NO_ENV_HINTS"] = "1"
            process.environment = env
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return (false, "") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus == 0, String(decoding: data, as: UTF8.self))
        }.value
    }

    private func loadOutdated() async {
        let result = await run(["outdated", "--json=v2"])
        guard let json = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any] else { outdated = []; return }
        func packages(_ key: String, cask: Bool) -> [Package] {
            (json[key] as? [[String: Any]] ?? []).map { item in
                Package(name: item["name"] as? String ?? "?",
                        installed: (item["installed_versions"] as? [String])?.last ?? "",
                        latest: item["current_version"] as? String, isCask: cask)
            }
        }
        outdated = packages("formulae", cask: false) + packages("casks", cask: true)
    }

    private func loadInstalled() async {
        async let formulae = run(["list", "--formula", "--versions"])
        async let casks = run(["list", "--cask", "--versions"])
        func parse(_ text: String, cask: Bool) -> [Package] {
            text.split(separator: "\n").map { line in
                let parts = line.split(separator: " ")
                return Package(name: String(parts.first ?? ""), installed: parts.dropFirst().joined(separator: " "), latest: nil, isCask: cask)
            }
        }
        installed = parse(await formulae.output, cask: false) + parse(await casks.output, cask: true)
    }

    func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { results = []; return }
        async let formulae = run(["search", "--formula", term])
        async let casks = run(["search", "--cask", term])
        func parse(_ text: String, cask: Bool) -> [Package] {
            text.split(separator: "\n").filter { !$0.hasPrefix("==>") && !$0.isEmpty }
                .map { Package(name: String($0), installed: "", latest: nil, isCask: cask) }
        }
        results = Array((parse(await formulae.output, cask: false) + parse(await casks.output, cask: true)).prefix(80))
    }

    private func loadServices() async {
        let result = await run(["services", "list", "--json"])
        let list = (try? JSONSerialization.jsonObject(with: Data(result.output.utf8))) as? [[String: Any]] ?? []
        services = list.map { Service(name: $0["name"] as? String ?? "?", status: $0["status"] as? String ?? "") }
    }

    /// Runs a brew command in a new session beside this pane, so its output (and any
    /// password prompt) is right there.
    func runInSession(_ arguments: String) {
        Workspace.shared.newSession(command: "brew " + arguments, cwd: NSHomeDirectory(), inNewPane: .vertical)
        let before = Set(DaemonClient.shared.sessions.map(\.id))
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            runningSession = DaemonClient.shared.sessions.first { !before.contains($0.id) }?.id
        }
    }

    /// Called when sessions change: a finished brew command refreshes the lists.
    func sessionsChanged(_ sessions: [SessionInfo]) {
        guard let id = runningSession, let session = sessions.first(where: { $0.id == id }), !session.isCommandRunning else { return }
        runningSession = nil
        Task { await load() }
    }
}

struct BrewPane: View {
    let paneID: UUID
    @StateObject private var model = BrewModel()
    @ObservedObject private var client = DaemonClient.shared
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(paneID: paneID, icon: "mug", title: "Homebrew", detail: nil) {
                if model.tab == .outdated && !model.outdated.isEmpty {
                    action("Upgrade All") { model.runInSession("upgrade") }
                }
                Segments(options: BrewModel.Tab.allCases.map { ($0, $0.rawValue) }, selection: $model.tab)
                IconButton(systemName: "arrow.clockwise", help: "Refresh") { Task { await model.load() } }
            }
            if model.missing {
                VStack(spacing: 10) {
                    Text("Homebrew isn't installed.").font(TypeScale.ui(13, .medium)).foregroundStyle(theme.text2.color)
                    Button("Install Homebrew in a Session") {
                        Workspace.shared.newSession(command: #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#)
                    }
                    .buttonStyle(.plain).font(TypeScale.ui(12, .semibold)).foregroundStyle(theme.text.color)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.loading && isEmpty {
                // Homebrew can take a few seconds; say what's happening instead of an empty list.
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.tab == .search ? "Searching…" : "Asking Homebrew…").font(TypeScale.ui(12)).foregroundStyle(theme.text3.color)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .background(theme.bg.color)
        .task { await model.load() }
        .onChange(of: model.tab) { _, _ in Task { await model.load() } }
        .onChange(of: client.sessions) { _, sessions in model.sessionsChanged(sessions) }
    }

    private var isEmpty: Bool {
        switch model.tab {
        case .outdated: return model.outdated.isEmpty
        case .installed: return model.installed.isEmpty
        case .search: return model.results.isEmpty
        case .services: return model.services.isEmpty
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.tab {
        case .outdated:
            list(model.outdated, empty: model.loading ? "" : "Everything is up to date.") { package in
                Text("\(package.installed) → \(package.latest ?? "?")").font(TypeScale.mono(11)).foregroundStyle(theme.text2.color)
                action("Upgrade") { model.runInSession("upgrade \(package.isCask ? "--cask " : "")\(package.name)") }
            } footer: { EmptyView() }
        case .installed:
            list(model.installed, empty: "") { package in
                Text(package.installed).font(TypeScale.mono(11)).foregroundStyle(theme.text3.color)
                action("Uninstall") { model.runInSession("uninstall \(package.isCask ? "--cask " : "")\(package.name)") }
            } footer: { EmptyView() }
        case .search:
            VStack(spacing: 0) {
                TextField("Search formulae and casks", text: $model.query)
                    .textFieldStyle(.plain).font(TypeScale.ui(13))
                    .padding(10)
                    .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
                    .onSubmit { Task { await model.search() } }
                list(model.results, empty: model.query.count < 2 ? "Type a name and press Return." : "Nothing found.") { package in
                    action("Install") { model.runInSession("install \(package.isCask ? "--cask " : "")\(package.name)") }
                } footer: { EmptyView() }
            }
        case .services:
            ScrollView {
                VStack(spacing: 0) {
                    if model.services.isEmpty { emptyText("No services.") }
                    ForEach(model.services) { service in
                        HStack(spacing: 10) {
                            Circle().fill(service.status == "started" ? theme.text.color : theme.text3.color.opacity(0.4)).frame(width: 6, height: 6)
                            Text(service.name).font(TypeScale.ui(12.5, .medium)).foregroundStyle(theme.text.color)
                            Text(service.status).font(TypeScale.ui(11.5)).foregroundStyle(theme.text3.color)
                            Spacer()
                            if service.status == "started" {
                                action("Restart") { model.runInSession("services restart \(service.name)") }
                                action("Stop") { model.runInSession("services stop \(service.name)") }
                            } else {
                                action("Start") { model.runInSession("services start \(service.name)") }
                            }
                        }
                        .frame(height: 34)
                        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func list<Trailing: View, Footer: View>(_ packages: [BrewModel.Package], empty: String,
                                                    @ViewBuilder trailing: @escaping (BrewModel.Package) -> Trailing,
                                                    @ViewBuilder footer: () -> Footer) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if packages.isEmpty && !empty.isEmpty { emptyText(empty) }
                ForEach(packages) { package in
                    HStack(spacing: 10) {
                        Text(package.name).font(TypeScale.ui(12.5, .medium)).foregroundStyle(theme.text.color)
                        if package.isCask { Text("cask").font(TypeScale.ui(10.5)).foregroundStyle(theme.text3.color) }
                        Spacer()
                        trailing(package)
                    }
                    .frame(height: 32)
                    .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
                }
                footer().padding(.top, 12)
            }
            .padding(.horizontal, 16)
        }
    }

    private func action(_ title: String, _ perform: @escaping () -> Void) -> some View {
        Button(title, action: perform).buttonStyle(.plain).font(TypeScale.ui(11.5, .medium)).foregroundStyle(theme.text.color)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text).font(TypeScale.ui(12)).foregroundStyle(theme.text3.color).frame(maxWidth: .infinity).padding(.top, 40)
    }
}
