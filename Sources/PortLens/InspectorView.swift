import AppKit
import SwiftUI
import PortLensCore

struct InspectorView: View {
    @ObservedObject var model: AppModel
    @State private var alias = ""

    var body: some View {
        Group {
            if let node = model.selectedNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            Image(systemName: node.symbol).font(.system(size: 25)).foregroundStyle(node.tint)
                                .frame(width: 52, height: 52).background(node.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            Spacer()
                            Text(node.transportTitle).font(.caption.weight(.medium)).foregroundStyle(node.tint)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.displayName(node)).font(.title3.weight(.semibold)).textSelection(.enabled)
                            Text(node.kindTitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            property("OSの表示名", node.name)
                            if let vendor = node.vendor { property("メーカー", vendor) }
                            if let speed = node.speed { property("接続速度の表示", speed) }
                            if let location = node.locationID { property("位置ID", location) }
                            ForEach(Array(node.properties.enumerated()), id: \.offset) { _, item in
                                property(item.label, item.value)
                            }
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 9) {
                            Text("このMacでの表示名").font(.subheadline.weight(.medium))
                            TextField("例：机の下のハブ", text: $alias).textFieldStyle(.roundedBorder)
                                .onSubmit { model.saveAlias(alias, for: node) }
                            HStack {
                                Button("保存") { model.saveAlias(alias, for: node) }
                                Button("元に戻す") { alias = ""; model.saveAlias("", for: node) }
                                    .disabled(model.aliases[node.id] == nil)
                            }
                            Text("接続位置が変わると、別の機器として扱われる場合があります。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Text("接続経路").font(.subheadline.weight(.medium))
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString((["Mac"] + model.path(to: node).map(model.displayName)).joined(separator: " → "), forType: .string)
                                } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.plain).help("接続経路をコピー").accessibilityLabel("接続経路をコピー")
                            }
                            Label("Mac", systemImage: "laptopcomputer").font(.caption)
                            ForEach(model.path(to: node)) { ancestor in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.tertiary)
                                    Text(model.displayName(ancestor))
                                }.font(.caption)
                            }
                        }
                        if node.kind == .hub {
                            Label("OS上の論理ハブです。製品内部のハブも含まれます。", systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if node.kind == .bus && node.children.isEmpty {
                            Label("この方式での機器表示はありません。物理ポートの空きを示すものではありません。", systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(22)
                }
                .onAppear { alias = model.aliases[node.id] ?? "" }
                .onChange(of: node.id) { _, _ in alias = model.aliases[node.id] ?? "" }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cursorarrow.click.2").font(.system(size: 30)).foregroundStyle(.teal)
                    Text("機器を選択").font(.headline)
                    Text("図や一覧から機器を選ぶと、\n接続経路と詳細が表示されます。")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("機器の制御や設定変更は行いません。")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Color(nsColor: .controlBackgroundColor))
    }

    private func property(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
