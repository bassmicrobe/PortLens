import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PortLensCore

enum DisplayMode: String, CaseIterable {
    case graph = "接続図"
    case list = "一覧"
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: DeviceSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var selection: String? = "all"
    @Published var selectedNodeID: String? {
        didSet { showInspector = selectedNode != nil }
    }
    @Published var query = ""
    @Published var displayMode: DisplayMode = .graph
    @Published var showInspector = false
    @Published var autoRefresh = false
    @Published var automaticallyFitsGraph = false
    @Published var zoom: Double = 1
    @Published private(set) var aliases: [String: String]
    @Published private(set) var addedCount = 0
    @Published private(set) var removedCount = 0
    let isDemo: Bool

    private let aliasKey = "PortLens.deviceAliases.v1"
    init(isDemo: Bool) {
        self.isDemo = isDemo
        aliases = UserDefaults.standard.dictionary(forKey: aliasKey) as? [String: String] ?? [:]
    }

    var roots: [DeviceNode] {
        guard let snapshot else { return [] }
        let all = snapshot.usbBuses + snapshot.thunderboltBuses
        switch selection {
        case "usb": return snapshot.usbBuses
        case "thunderbolt": return snapshot.thunderboltBuses
        case nil, "all": return all
        default: return all.filter { $0.id == selection }
        }
    }

    var visibleRoots: [DeviceNode] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return roots }
        return roots.compactMap { filtered($0, term: term) }
    }

    var visibleNodes: [DeviceNode] { visibleRoots.flatMap(\.flattened) }
    var selectedNode: DeviceNode? { snapshot?.allNodes.first { $0.id == selectedNodeID } }
    var title: String {
        switch selection {
        case nil, "all": return "すべての接続"
        case "usb": return "USB"
        case "thunderbolt": return "Thunderbolt / USB4"
        default: return roots.first.map(displayName) ?? "接続"
        }
    }
    var usbDeviceCount: Int { count(.usb, kind: .device) }
    var usbHubCount: Int { count(.usb, kind: .hub) }
    var thunderboltDeviceCount: Int { count(.thunderbolt, kind: .device) }

    func displayName(_ node: DeviceNode) -> String { aliases[node.id] ?? node.name }
    func saveAlias(_ value: String, for node: DeviceNode) {
        let value = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        if value.isEmpty || value == node.name { aliases.removeValue(forKey: node.id) }
        else { aliases[node.id] = value }
        UserDefaults.standard.set(aliases, forKey: aliasKey)
    }
    func selectNode(_ node: DeviceNode) { selectedNodeID = node.id }
    func path(to node: DeviceNode) -> [DeviceNode] {
        for root in (snapshot?.usbBuses ?? []) + (snapshot?.thunderboltBuses ?? []) {
            if let result = findPath(root, target: node.id) { return result }
        }
        return []
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh: DeviceSnapshot
            if isDemo { fresh = .demo } else { fresh = try await DeviceCollector.collect() }
            if let previous = snapshot {
                let oldIDs = Set(previous.allNodes.filter { $0.kind != .bus }.map(\.id))
                let newIDs = Set(fresh.allNodes.filter { $0.kind != .bus }.map(\.id))
                addedCount = newIDs.subtracting(oldIDs).count
                removedCount = oldIDs.subtracting(newIDs).count
            }
            snapshot = fresh
            errorMessage = nil
            if let selectedNodeID, !fresh.allNodes.contains(where: { $0.id == selectedNodeID }) {
                self.selectedNodeID = nil
            }
            if let selection, !["all", "usb", "thunderbolt"].contains(selection),
               !(fresh.usbBuses + fresh.thunderboltBuses).contains(where: { $0.id == selection }) {
                self.selection = "all"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportSnapshot() {
        guard let snapshot else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PortLens-\(snapshot.capturedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
        panel.title = "接続情報を書き出す"
        panel.message = "機器名・接続経路・取得日時を書き出します。シリアル番号は含みません。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: url, options: .atomic)
        } catch { errorMessage = "書き出しに失敗しました: \(error.localizedDescription)" }
    }

    private func count(_ transport: DeviceTransport, kind: DeviceKind) -> Int {
        snapshot?.allNodes.filter { $0.transport == transport && $0.kind == kind }.count ?? 0
    }
    private func filtered(_ node: DeviceNode, term: String) -> DeviceNode? {
        let fields = [displayName(node), node.name, node.vendor ?? "", node.locationID ?? ""]
        if fields.contains(where: { $0.localizedCaseInsensitiveContains(term) }) { return node }
        let children = node.children.compactMap { filtered($0, term: term) }
        guard !children.isEmpty else { return nil }
        return DeviceNode(id: node.id, name: node.name, vendor: node.vendor, transport: node.transport,
                          kind: node.kind, speed: node.speed, locationID: node.locationID,
                          properties: node.properties, children: children)
    }
    private func findPath(_ node: DeviceNode, target: String) -> [DeviceNode]? {
        if node.id == target { return [node] }
        for child in node.children {
            if let path = findPath(child, target: target) { return [node] + path }
        }
        return nil
    }
}

extension DeviceNode {
    var transportTitle: String { transport == .usb ? "USB" : "Thunderbolt / USB4" }
    var kindTitle: String {
        switch kind { case .bus: return "バス"; case .hub: return "論理ハブ"; case .device: return "機器・機能" }
    }
    var tint: Color { transport == .usb ? .blue : .purple }
    var symbol: String {
        if kind == .bus { return "point.3.connected.trianglepath.dotted" }
        if kind == .hub { return "externaldrive.connected.to.line.below" }
        let n = name.lowercased()
        if n.contains("keyboard") || n.contains("keychron") { return "keyboard" }
        if n.contains("monitor") || n.contains("display") || n.contains("u402") { return "display" }
        if n.contains("ilok") || n.contains("licenser") { return "key" }
        if n.contains("receiver") || n.contains("trackball") { return "computermouse" }
        if n.contains("card reader") { return "sdcard" }
        if n.contains("lan") || n.contains("ethernet") { return "network" }
        if n.contains("dock") || n.contains("raid") { return "externaldrive" }
        if n.contains("lyra") || n.contains("audio") || n.contains("uf8") || n.contains("mio") || n.contains("drm") { return "waveform" }
        return "cable.connector"
    }
}
