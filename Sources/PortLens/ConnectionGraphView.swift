import SwiftUI
import PortLensCore

struct ConnectionGraphView: View {
    @ObservedObject var model: AppModel
    @State private var collapsed: Set<String> = []
    @State private var initialized = false
    @State private var viewportSize: CGSize = .zero
    private let fitPadding: CGFloat = 16

    var body: some View {
        let layout = ConnectionDiagram(roots: model.visibleRoots, collapsed: model.query.isEmpty ? collapsed : [])
        GeometryReader { _ in
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Label("USB", systemImage: "circle.fill").foregroundStyle(.blue)
                    Label("Thunderbolt / USB4", systemImage: "circle.fill").foregroundStyle(.purple)
                    Spacer(minLength: 4)
                    Button("折りたたむ") { collapsed = Set(model.roots.filter { !$0.children.isEmpty }.map(\.id)) }
                        .disabled(!model.query.isEmpty)
                    Button("展開") { collapsed = [] }.disabled(!model.query.isEmpty)
                    Divider().frame(height: 16)
                    Button { adjustZoom(direction: -1, layout: layout) } label: { Image(systemName: "minus.magnifyingglass") }
                        .accessibilityLabel("縮小")
                    Button {
                        model.zoom = 1
                        model.automaticallyFitsGraph = false
                    } label: {
                        Text(Double(zoomScale(for: layout)).formatted(.percent.precision(.significantDigits(1...3))))
                            .monospacedDigit().frame(width: 48)
                    }
                    .help("100%の大きさに戻す")
                    .accessibilityLabel("100%の大きさに戻す")
                    .accessibilityValue(Double(zoomScale(for: layout)).formatted(.percent))
                    Button { adjustZoom(direction: 1, layout: layout) } label: { Image(systemName: "plus.magnifyingglass") }
                        .accessibilityLabel("拡大")
                    Button("全体") {
                        model.automaticallyFitsGraph = true
                    }
                    .foregroundStyle(model.automaticallyFitsGraph ? Color.teal : Color.primary)
                    .help("図全体が収まるように自動調整。ウィンドウのサイズ変更にも追従します。")
                    .accessibilityValue(model.automaticallyFitsGraph ? "自動調整中" : "手動ズーム")
                }
                .font(.system(size: 11)).buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 12)
                if let selected = model.selectedNode, !highlightedRoute(in: layout).isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .foregroundStyle(selected.tint)
                        Text("接続経路：\(model.displayName(selected))").lineLimit(1)
                        Spacer(minLength: 0)
                        Button("強調を解除") { model.selectedNodeID = nil }.buttonStyle(.borderless)
                    }
                    .font(.caption)
                    .padding(.horizontal, 16).padding(.bottom, 10)
                }
                GeometryReader { viewport in
                    let scale = zoomScale(for: layout, viewport: viewport.size)
                    ScrollViewReader { scrollProxy in
                        ScrollView([.horizontal, .vertical]) {
                            ZStack(alignment: .topLeading) {
                                Canvas { context, _ in
                                    drawConnections(in: &context, layout: layout, route: highlightedRoute(in: layout))
                                }.frame(width: layout.size.width, height: layout.size.height).accessibilityHidden(true)
                                ForEach(layout.sections) { section in
                                    HStack(spacing: 8) {
                                        Image(systemName: section.transport == .usb ? "cable.connector" : "bolt.fill")
                                            .foregroundStyle(section.transport == .usb ? Color.blue : Color.purple)
                                        Text(section.title).fontWeight(.semibold)
                                        Text("接続系統").foregroundStyle(.secondary)
                                    }
                                    .font(.system(size: 13))
                                    .fixedSize()
                                    .frame(width: ConnectionDiagram.cardWidth, alignment: .leading)
                                    .position(section.labelPoint)
                                }
                                ForEach(layout.nodes) { item in
                                    if let node = item.device {
                                        nodeCard(node)
                                            .position(item.center)
                                    } else {
                                        macCard(transport: item.transport).position(item.center)
                                    }
                                }
                            }
                            .frame(width: layout.size.width, height: layout.size.height)
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(width: layout.size.width * scale, height: layout.size.height * scale, alignment: .topLeading)
                            .padding(fitPadding)
                            .frame(minWidth: viewport.size.width, minHeight: viewport.size.height, alignment: .topLeading)
                            .contentShape(Rectangle())
                            .simultaneousGesture(SpatialTapGesture().onEnded { event in
                                // The gesture covers the canvas, including unused viewport
                                // space. Exclude cards so their buttons keep their behavior.
                                let point = CGPoint(x: (event.location.x - fitPadding) / scale,
                                                    y: (event.location.y - fitPadding) / scale)
                                let isOnCard = layout.nodes.contains { item in
                                    CGRect(x: item.center.x - ConnectionDiagram.cardWidth / 2,
                                           y: item.center.y - ConnectionDiagram.cardHeight / 2,
                                           width: ConnectionDiagram.cardWidth,
                                           height: ConnectionDiagram.cardHeight).contains(point)
                                }
                                if !isOnCard { model.selectedNodeID = nil }
                            })
                            .id("diagram-origin")
                        }
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
                        .onChange(of: viewport.size, initial: true) { _, size in
                            viewportSize = size
                        }
                        .onChange(of: model.automaticallyFitsGraph) { _, enabled in
                            if enabled { scrollProxy.scrollTo("diagram-origin", anchor: .topLeading) }
                        }
                    }
                }
            }
        }
        .onAppear { initializeCollapse() }
        .onChange(of: model.selection) { _, _ in
            collapsed = []
            initialized = false
            initializeCollapse()
        }
    }

    private func zoomScale(for layout: ConnectionDiagram, viewport: CGSize? = nil) -> CGFloat {
        guard model.automaticallyFitsGraph else { return CGFloat(model.zoom) }
        // Measure the actual canvas viewport after toolbars and inspector layout,
        // rather than estimating it from the total window's dimensions.
        return DiagramZoom.fitScale(content: layout.size, viewport: viewport ?? viewportSize, padding: fitPadding)
    }

    private func adjustZoom(direction: Int, layout: ConnectionDiagram) {
        model.zoom = Double(DiagramZoom.adjustedScale(current: zoomScale(for: layout), direction: direction))
        model.automaticallyFitsGraph = false
    }

    private func highlightedRoute(in layout: ConnectionDiagram) -> Set<String> {
        guard let selected = model.selectedNode else { return [] }
        let visibleIDs = Set(layout.nodes.map(\.id))
        var route = Set(model.path(to: selected).map(\.id)).intersection(visibleIDs)
        guard !route.isEmpty else { return [] }
        route.insert("portlens:mac:\(selected.transport.rawValue)")
        return route
    }

    private func drawConnections(in context: inout GraphicsContext, layout: ConnectionDiagram, route: Set<String>) {
        // A parent owns one shared trunk. Drawing each complete parent→child
        // path separately would overpaint the trunk and recreate the dense fan.
        for connection in layout.connections {
            let color: Color = connection.transport == .usb ? .blue : .purple
            let tint = color.opacity(route.isEmpty ? 0.55 : 0.16)
            guard let last = connection.targets.last else { continue }
            var trunk = Path()
            trunk.move(to: connection.source)
            trunk.addLine(to: CGPoint(x: connection.trunkX, y: connection.source.y))
            trunk.addLine(to: CGPoint(x: connection.trunkX, y: last.point.y))
            context.stroke(trunk, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            for target in connection.targets {
                let junction = CGPoint(x: connection.trunkX, y: target.point.y)
                var branch = Path()
                branch.move(to: junction)
                branch.addLine(to: target.point)
                context.stroke(branch, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                if connection.targets.count > 1 {
                    context.fill(Path(ellipseIn: CGRect(x: junction.x - 2, y: junction.y - 2, width: 4, height: 4)), with: .color(tint))
                }
            }
        }
        // Only the part of the trunk leading to the selected branch is active.
        // The rest remains subdued, including all unrelated siblings.
        for connection in layout.connections where route.contains(connection.parentID) {
            guard let target = connection.targets.first(where: { route.contains($0.childID) }) else { continue }
            let color: Color = connection.transport == .usb ? .blue : .purple
            var path = Path()
            path.move(to: connection.source)
            path.addLine(to: CGPoint(x: connection.trunkX, y: connection.source.y))
            path.addLine(to: CGPoint(x: connection.trunkX, y: target.point.y))
            path.addLine(to: target.point)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    private func initializeCollapse() {
        guard !initialized else { return }
        initialized = true
        // A large setup first shows its buses, so the overview remains readable.
        // Selecting a single bus in the sidebar shows that whole branch.
        if model.roots.count > 3 && model.visibleNodes.count > 30 {
            collapsed = Set(model.roots.filter { !$0.children.isEmpty }.map(\.id))
        }
    }

    private func macCard(transport: DeviceTransport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer").font(.system(size: 27)).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.isDemo ? "Demo Mac" : "このMac").font(.system(size: 15, weight: .semibold))
                Text(transport == .usb ? "USB 接続" : "Thunderbolt / USB4 接続")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(16).frame(width: ConnectionDiagram.cardWidth, height: ConnectionDiagram.cardHeight)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.teal.opacity(0.4), lineWidth: 1))
    }

    private func nodeCard(_ node: DeviceNode) -> some View {
        let selected = model.selectedNodeID == node.id
        let isCollapsed = collapsed.contains(node.id) && model.query.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Button { model.selectNode(node) } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: node.symbol).font(.system(size: 19)).foregroundStyle(node.tint).frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.displayName(node)).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(node.speed ?? node.kindTitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.padding(.horizontal, 13).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(model.displayName(node))、\(node.kindTitle)、詳細を表示")
            if !node.children.isEmpty {
                HStack {
                    Text("下流 \(node.children.flatMap(\.flattened).filter { $0.kind == .device }.count) 機器・機能")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Button {
                        if collapsed.contains(node.id) { collapsed.remove(node.id) } else { collapsed.insert(node.id) }
                    } label: {
                        Label(isCollapsed ? "展開" : "閉じる", systemImage: isCollapsed ? "chevron.right" : "chevron.down")
                    }.buttonStyle(.plain).foregroundStyle(node.tint).disabled(!model.query.isEmpty)
                        .accessibilityLabel("\(model.displayName(node))を\(isCollapsed ? "展開" : "折りたたむ")")
                }.font(.system(size: 10)).padding(.horizontal, 13).padding(.bottom, 9)
            }
        }
        .frame(width: ConnectionDiagram.cardWidth, height: ConnectionDiagram.cardHeight)
        .background(selected ? node.tint.opacity(0.09) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? node.tint : Color.primary.opacity(0.13), lineWidth: selected ? 2 : 1))
        .help("\(model.displayName(node)) · \(node.kindTitle)")
    }
}
