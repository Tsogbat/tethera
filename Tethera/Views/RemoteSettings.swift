import SwiftUI
import TetheraKit

/// Settings → Remote: other Macs whose sessions show in the sidebar.
struct RemoteSettings: View {
    @ObservedObject private var store = PreferencesStore.shared
    @ObservedObject private var client = DaemonClient.shared
    @ObservedObject private var phone = PhoneServer.shared
    @State private var adding = false
    @State private var pushSent = false

    var body: some View {
        Form {
            Section {
                if store.value.remoteHosts.isEmpty {
                    Text("No other Macs yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.value.remoteHosts) { host in
                    HostRow(host: host, status: client.remoteStatus[host.id] ?? .connecting) {
                        store.value.remoteHosts.removeAll { $0.id == host.id }
                        client.syncRemoteHosts(store.value.remoteHosts)
                    }
                }
                HStack {
                    Spacer()
                    Button("Add Mac…") { adding = true }
                }
            } header: {
                PlanHeader(title: "Other Macs", plan: .pro)
            } footer: {
                Text("Their sessions show in the sidebar under the Mac's name, and you can start new ones there. Tethera connects with your own ssh, so ~/.ssh/config, keys, and Tailscale SSH work as they do in Terminal. Changes, Git, and transcripts need the files, so they stay on the Mac you're at.")
                    .foregroundStyle(.secondary)
            }
            phoneSection
            pushSection
            Section {
                LabeledContent("This Mac") {
                    Text(ProcessInfo.processInfo.hostName)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("On the other Mac") {
                    Text("Install Tethera, then turn on Remote Login in System Settings → General → Sharing.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Reaching this Mac from another")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $adding) {
            AddHostSheet(existing: store.value.remoteHosts.map(\.address)) { host in
                store.value.remoteHosts.append(host)
                client.syncRemoteHosts(store.value.remoteHosts)
            }
        }
    }
}

extension RemoteSettings {
    @ViewBuilder
    private var phoneSection: some View {
        Section {
            Toggle("Phone dashboard", isOn: Binding(
                get: { store.value.phoneEnabled },
                set: { on in
                    if on && store.value.phoneToken == nil { store.value.phoneToken = PhoneServer.randomToken() }
                    store.value.phoneEnabled = on
                }))
            if store.value.phoneEnabled {
                Picker("Reachable over", selection: $store.value.phoneReach) {
                    ForEach(PhoneReach.allCases) { Text($0.label).tag($0) }
                }
                if let url = phone.pairingURL {
                    HStack(alignment: .top, spacing: 16) {
                        if let code = PhoneServer.qrCode(for: url, size: 132) {
                            Image(nsImage: code)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 132, height: 132)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Scan with your phone's camera, then add the page to your Home Screen.")
                            Text(phone.baseURL?.absoluteString ?? "")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            HStack {
                                Button("Copy Link") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                }
                                Button("New Pairing Code") { store.value.phoneToken = PhoneServer.randomToken() }
                                    .help("Unpairs every phone that has the old code")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let problem = phone.problem {
                    Text(problem).foregroundStyle(.red)
                }
            }
        } header: {
            PlanHeader(title: "Phone", plan: .pro)
        } footer: {
            Text(store.value.phoneReach == .tailscale
                 ? "Shows your agents and approvals; you can allow, deny, or answer an agent that's waiting, but it can't open a shell. Over Tailscale only your own devices reach it, and the connection is encrypted."
                 : "Shows your agents and approvals; you can allow, deny, or answer an agent that's waiting, but it can't open a shell. On a local network the page is plain HTTP, so use it on networks you trust.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var pushSection: some View {
        Section {
            Toggle("Push to my phone while I'm away", isOn: Binding(
                get: { store.value.pushEnabled },
                set: { on in
                    if on && store.value.pushTopic == nil { store.value.pushTopic = PushNotifier.newTopic() }
                    store.value.pushEnabled = on
                }))
            if store.value.pushEnabled, let topic = store.value.pushTopic {
                LabeledContent("Topic") {
                    HStack {
                        Text(topic)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(topic, forType: .string)
                        }
                    }
                }
                TextField("Server", text: Binding(
                    get: { store.value.pushServer ?? "" },
                    set: { store.value.pushServer = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }),
                    prompt: Text(PushNotifier.defaultServer))
                HStack {
                    Text("Subscribe to the topic in the ntfy app, then send a test.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(pushSent ? "Sent" : "Send Test Push") {
                        PushNotifier.shared.sendTest()
                        pushSent = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { pushSent = false }
                    }
                    .disabled(pushSent)
                }
            }
        } header: {
            PlanHeader(title: "Push", plan: .pro)
        } footer: {
            Text("After two minutes away from this Mac, agents that need you, finish, or fail push to your phone through ntfy, a free push service (or your own ntfy server). A push carries the agent, the session's name, and one line, never terminal output. Allow and Deny on a push work where the phone dashboard is reachable.")
                .foregroundStyle(.secondary)
        }
    }
}

/// A settings section title with the plan it belongs to.
struct PlanHeader: View {
    let title: String
    let plan: Plan

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(plan.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .help("\(plan.title) is free during the beta")
        }
    }
}

private struct HostRow: View {
    let host: RemoteHost
    let status: DaemonClient.Status
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(isFailed ? Color.red : .secondary)
                    .lineLimit(2)
            }
            Spacer()
            if isFailed {
                Button("Retry") { DaemonClient.shared.retry(host.id) }
            }
            Button("Remove", action: remove)
        }
    }

    private var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    private var detail: String {
        switch status {
        case .connected:
            let count = DaemonClient.shared.sessions.filter { $0.host == host.id }.count
            return "\(host.address) · \(count) \(count == 1 ? "session" : "sessions")"
        case .connecting: return "\(host.address) · connecting…"
        case .failed(let message): return message
        }
    }
}

/// Name and ssh address, checked before it's added.
private struct AddHostSheet: View {
    let existing: [String]
    let add: (RemoteHost) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var checking = false
    @State private var result: Result<String, DaemonClient.CheckFailure>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a Mac")
                .font(.headline)
            Form {
                TextField("Address", text: $address, prompt: Text("studio.local, me@10.0.0.4, or a Tailscale name"))
                    .onChange(of: address) { _, _ in result = nil }
                TextField("Name", text: $name, prompt: Text(suggestedName.isEmpty ? "Studio" : suggestedName))
            }
            .formStyle(.columns)
            Group {
                switch result {
                case .success(let version):
                    Label("Reached it. \(version.isEmpty ? "Tethera is installed." : version)", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                case .failure(let failure):
                    Label(failure.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                case nil where isDuplicate:
                    Text("That Mac is already in the list.")
                        .foregroundStyle(.secondary)
                case nil:
                    Text("Tethera runs `ssh \(address.isEmpty ? "address" : address) tethera bridge`. The Mac needs Remote Login on, Tethera installed, and a key or Tailscale SSH, since there's no password prompt.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                if checking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if case .success = result {
                    Button("Add") {
                        add(RemoteHost(name: name.isEmpty ? suggestedName : name, address: trimmedAddress))
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Check") { check() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(trimmedAddress.isEmpty || checking || isDuplicate)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var trimmedAddress: String { address.trimmingCharacters(in: .whitespaces) }
    private var isDuplicate: Bool { existing.contains { $0.caseInsensitiveCompare(trimmedAddress) == .orderedSame } }

    /// "me@studio.local" → "studio".
    private var suggestedName: String {
        let host = trimmedAddress.split(separator: "@").last.map(String.init) ?? ""
        return host.split(separator: ".").first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? ""
    }

    private func check() {
        checking = true
        let address = trimmedAddress
        Task {
            let outcome = await DaemonClient.check(address)
            checking = false
            result = outcome
        }
    }
}
