import AppKit
import SwiftUI
import PortLensCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            VStack(spacing: 0) {
                header
                if let message = model.errorMessage {
                    notice(message, symbol: "exclamationmark.triangle", color: .orange)
                }
                if let snapshot = model.snapshot, !snapshot.warnings.isEmpty {
                    notice(snapshot.warnings.joined(separator: " · "), symbol: "info.circle", color: .secondary)
                }
                Divider()
                content
                Divider()
                footer
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .inspector(isPresented: $model.showInspector) {
                InspectorView(model: model)
                    .inspectorColumnWidth(min: 260, ideal: 290, max: 360)
            }
        }
        .navigationTitle("PortLens")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isLoading { ProgressView().controlSize(.small) }
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("接続情報を更新（⌘R）")
                    .accessibilityLabel("接続情報を更新")
                    .disabled(model.isLoading)
                Button { model.exportSnapshot() } label: { Image(systemName: "square.and.arrow.up") }
                    .help("JSONを書き出す")
                    .accessibilityLabel("JSONを書き出す")
                    .disabled(model.snapshot == nil)
                Button { model.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                    .help("機器の詳細を表示")
                    .accessibilityLabel("機器の詳細を表示")
                    .disabled(model.selectedNode == nil)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                if let logo = colorScheme == .dark ? BrandResources.darkLogo : BrandResources.lightLogo {
                    Image(nsImage: logo)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 172, height: 32)
                        .accessibilityLabel("PortLens")
                } else {
                    Text("PortLens").font(.system(size: 20, weight: .semibold, design: .rounded))
                }
                Text("Macのつながりを、ひと目で。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            List(selection: $model.selection) {
                Section("表示する接続") {
                    navigationRow("すべての接続", symbol: "laptopcomputer", selection: "all")
                    navigationRow("USB", symbol: "cable.connector", selection: "usb")
                    navigationRow("Thunderbolt / USB4", symbol: "bolt.fill", selection: "thunderbolt")
                }
                if let snapshot = model.snapshot {
                    Section("USBバス") {
                        ForEach(snapshot.usbBuses) { node in busRow(node) }
                    }
                    Section("Thunderbolt / USB4バス") {
                        ForEach(snapshot.thunderboltBuses) { node in busRow(node) }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Toggle("10秒ごとに更新", isOn: $model.autoRefresh).toggleStyle(.switch).controlSize(.small)
                    .disabled(model.isDemo)
                Label(model.isDemo ? "デモデータを表示中" : "このMac内で読み取り", systemImage: model.isDemo ? "play.rectangle" : "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func navigationRow(_ title: String, symbol: String, selection: String) -> some View {
        SidebarRow(title: title, symbol: symbol)
            .tag(selection)
    }

    private func busRow(_ node: DeviceNode) -> some View {
        // The section already names the transport. Keep default bus titles short
        // enough for the narrow sidebar, while preserving user-supplied aliases.
        let title = model.aliases[node.id] ?? node.name.replacingOccurrences(of: "Thunderbolt / USB4 ", with: "")
        return SidebarRow(title: title, dotColor: node.tint.opacity(node.children.isEmpty ? 0.3 : 0.9),
                          count: node.flattened.filter { $0.kind == .device }.count)
            .help(model.displayName(node))
            .tag(node.id)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(model.title).font(.system(size: 25, weight: .semibold))
                        if model.isDemo {
                            Text("DEMO").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(.orange.opacity(0.1), in: Capsule())
                        }
                    }
                    Text("OSが認識している接続経路を表示します")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("表示形式", selection: $model.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 130)
            }
            HStack(spacing: 22) {
                metric("USB機器・機能", value: model.usbDeviceCount, color: .blue)
                metric("論理USBハブ", value: model.usbHubCount, color: .secondary)
                metric("Thunderbolt / USB4機器", value: model.thunderboltDeviceCount, color: .purple)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("機器名・メーカー・位置IDで検索", text: $model.query)
                    .textFieldStyle(.plain).accessibilityLabel("機器を検索")
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("検索をクリア")
                }
            }.padding(9).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }.padding(22)
    }

    private func metric(_ title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.snapshot == nil ? "—" : "\(value)")
                .font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(color).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var content: some View {
        if model.snapshot == nil {
            VStack(spacing: 16) {
                if model.isLoading {
                    ProgressView()
                    Text("接続情報を読み取っています").font(.headline)
                    Text("USBとThunderboltの構成を確認しています。初回は少し時間がかかる場合があります。")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else {
                    Image(systemName: "cable.connector.slash").font(.largeTitle).foregroundStyle(.secondary)
                    Text("接続情報を取得できませんでした").font(.headline)
                    Button("再試行") { Task { await model.refresh() } }
                }
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.visibleRoots.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else if model.displayMode == .graph {
            ConnectionGraphView(model: model)
        } else {
            DeviceListView(model: model)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let date = model.snapshot?.capturedAt {
                Label("取得 \(date.formatted(date: .omitted, time: .standard))", systemImage: "clock")
                    .help(date.formatted(date: .complete, time: .standard))
            }
            if model.addedCount > 0 || model.removedCount > 0 {
                Text("前回比 +\(model.addedCount) / −\(model.removedCount)")
                    .help("前回の取得から増減した論理ノード数")
            }
            Spacer(minLength: 0)
            Text(model.errorMessage == nil ? "論理構成を表示 · 物理的な台数とは異なります" : "前回取得した情報を表示しています")
                .lineLimit(1)
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 10)
    }

    private func notice(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.bottom, 12)
            .textSelection(.enabled)
    }
}

struct DeviceListView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Table(model.visibleNodes, selection: $model.selectedNodeID) {
            TableColumn("機器・機能") { node in
                HStack(spacing: 8) {
                    Image(systemName: node.symbol).foregroundStyle(node.tint).frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.displayName(node)).lineLimit(1)
                        if let vendor = node.vendor, !vendor.isEmpty {
                            Text(vendor).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.padding(.vertical, 5)
                }
            }.width(min: 180, ideal: 240)
            TableColumn("種別") { node in Text(node.kindTitle).foregroundStyle(.secondary) }.width(78)
            TableColumn("接続") { node in Text(node.transport == .usb ? "USB" : "TB / USB4") }.width(75)
            TableColumn("速度") { node in Text(node.speed ?? "—").font(.caption) }.width(min: 80, ideal: 120)
        }
    }
}
