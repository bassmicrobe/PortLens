import Foundation
import CoreGraphics

public struct DiagramNode: Identifiable {
    public let id: String
    public let device: DeviceNode?
    public let transport: DeviceTransport
    public let center: CGPoint
}

public struct DiagramTarget {
    public let childID: String
    public let point: CGPoint
}

/// A single parent junction. Render its trunk once, then its child branches;
/// generating one complete path per target would overdraw the shared trunk.
public struct DiagramConnection {
    public let parentID: String
    public let transport: DeviceTransport
    public let source: CGPoint
    public let trunkX: CGFloat
    public let targets: [DiagramTarget]
}

public struct DiagramSection: Identifiable {
    public var id: String { transport.rawValue }
    public let transport: DeviceTransport
    public let title: String
    /// Center anchor for a card-width title frame, above its first card row.
    public let labelPoint: CGPoint
    public let bounds: CGRect
}

/// Display-only layout for the two OS transport trees, arranged side by side.
/// The repeated Mac card anchors each section; it never adds a physical device
/// to the inventory.
public struct ConnectionDiagram {
    public static let cardWidth: CGFloat = 222
    public static let cardHeight: CGFloat = 90
    public let nodes: [DiagramNode]
    public let connections: [DiagramConnection]
    public let sections: [DiagramSection]
    public let size: CGSize

    public init(roots: [DeviceNode], collapsed: Set<String>) {
        let padding: CGFloat = 28
        let horizontalGap: CGFloat = 110
        let leafGap: CGFloat = 34
        let rootGap: CGFloat = 20
        let sectionGap: CGFloat = 64
        let headerHeight: CGFloat = 48
        let step = Self.cardWidth + horizontalGap
        var placed: [DiagramNode] = []
        var branches: [DiagramConnection] = []
        var groups: [DiagramSection] = []
        let sectionTop = padding
        var sectionLeft: CGFloat = 0

        func connection(parentID: String, transport: DeviceTransport,
                        center: CGPoint, children: [(String, CGPoint)]) -> DiagramConnection {
            let source = CGPoint(x: center.x + Self.cardWidth / 2, y: center.y)
            let targets = children.map {
                DiagramTarget(childID: $0.0, point: CGPoint(x: $0.1.x - Self.cardWidth / 2, y: $0.1.y))
            }
            return DiagramConnection(parentID: parentID, transport: transport,
                                     source: source, trunkX: source.x + horizontalGap / 2,
                                     targets: targets)
        }

        for transport in DeviceTransport.allCases {
            let sectionRoots = roots.filter { $0.transport == transport }
            guard !sectionRoots.isEmpty else { continue }
            var cursor = sectionTop + headerHeight
            var deepest = 1
            let firstNodeIndex = placed.count

            func place(_ device: DeviceNode, depth: Int) -> CGPoint {
                deepest = max(deepest, depth)
                let children = collapsed.contains(device.id) ? [] : device.children
                let childrenPlaced = children.map { ($0.id, place($0, depth: depth + 1)) }
                let y: CGFloat
                if let firstChild = childrenPlaced.first {
                    y = firstChild.1.y
                } else {
                    y = cursor + Self.cardHeight / 2
                    cursor += Self.cardHeight + leafGap
                }
                let center = CGPoint(x: sectionLeft + padding + Self.cardWidth / 2 + CGFloat(depth) * step, y: y)
                placed.append(DiagramNode(id: device.id, device: device, transport: transport, center: center))
                if !childrenPlaced.isEmpty {
                    branches.append(connection(parentID: device.id, transport: transport,
                                               center: center, children: childrenPlaced))
                }
                return center
            }

            var rootsPlaced: [(String, CGPoint)] = []
            for root in sectionRoots {
                rootsPlaced.append((root.id, place(root, depth: 1)))
                cursor += rootGap
            }
            let macID = "portlens:mac:\(transport.rawValue)"
            let macCenter = CGPoint(x: sectionLeft + padding + Self.cardWidth / 2,
                                    y: rootsPlaced[0].1.y)
            placed.append(DiagramNode(id: macID, device: nil, transport: transport, center: macCenter))
            branches.append(connection(parentID: macID, transport: transport,
                                       center: macCenter, children: rootsPlaced))

            let width = padding * 2 + Self.cardWidth + CGFloat(deepest) * step
            let bottom = placed[firstNodeIndex...].map { $0.center.y + Self.cardHeight / 2 }.max()! + padding
            groups.append(DiagramSection(transport: transport,
                                         title: transport == .usb ? "USB" : "Thunderbolt / USB4",
                                         labelPoint: CGPoint(x: sectionLeft + padding + Self.cardWidth / 2, y: sectionTop + 12),
                                         bounds: CGRect(x: sectionLeft, y: sectionTop, width: width, height: bottom - sectionTop)))
            sectionLeft += width + sectionGap
        }

        nodes = placed
        connections = branches
        sections = groups
        size = CGSize(width: groups.last?.bounds.maxX ?? padding * 2 + Self.cardWidth,
                      height: max((groups.map { $0.bounds.maxY }.max() ?? 0) + padding, 160))
    }
}
