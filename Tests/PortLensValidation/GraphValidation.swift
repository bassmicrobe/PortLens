import Foundation
import CoreGraphics
import PortLensCore

public enum GraphValidation {
    public static var cases: [CoreValidationCase] {
        [
            CoreValidationCase(name: "testDiagramSeparatesTransportSections", run: testDiagramSeparatesTransportSections),
            CoreValidationCase(name: "testDiagramCollapsingRemovesHiddenDescendants", run: testDiagramCollapsingRemovesHiddenDescendants),
            CoreValidationCase(name: "testDiagramRoutesOutsideCardsAndWithinBounds", run: testDiagramRoutesOutsideCardsAndWithinBounds),
            CoreValidationCase(name: "testDiagramUsesOneSharedTrunkPerParent", run: testDiagramUsesOneSharedTrunkPerParent),
            CoreValidationCase(name: "testDiagramHandlesEmptyAndFilteredTrees", run: testDiagramHandlesEmptyAndFilteredTrees)
        ]
    }

    public static func testDiagramSeparatesTransportSections() throws {
        let diagram = ConnectionDiagram(roots: crowdedRoots, collapsed: [])
        try check(diagram.sections.map(\.transport) == [.usb, .thunderbolt], "Expected separate USB and Thunderbolt sections")
        try check(diagram.nodes.filter { $0.device == nil }.count == 2, "Each section needs one display-only Mac anchor")
        try check(Set(diagram.nodes.map(\.id)).count == diagram.nodes.count, "Node IDs must remain unique")
        let usb = diagram.sections[0]
        let thunderbolt = diagram.sections[1]
        try check(usb.bounds.maxX < thunderbolt.bounds.minX, "USB and Thunderbolt must appear side by side without overlapping")
        try check(usb.labelPoint.y == thunderbolt.labelPoint.y, "Transport headings must share the top row")
        try check(usb.bounds.minY == thunderbolt.bounds.minY, "Transport sections must start at the same height")
        let byID = Dictionary(uniqueKeysWithValues: diagram.nodes.map { ($0.id, $0) })
        for connection in diagram.connections {
            try check(byID[connection.parentID]?.transport == connection.transport, "Parent must belong to its transport section")
            for target in connection.targets {
                try check(byID[target.childID]?.transport == connection.transport, "A branch must not cross transport sections")
            }
        }
    }

    public static func testDiagramCollapsingRemovesHiddenDescendants() throws {
        let roots = crowdedRoots
        let full = ConnectionDiagram(roots: roots, collapsed: [])
        let hub = roots[0].children[0]
        let hidden = Set(hub.children.flatMap(\.flattened).map(\.id))
        let collapsed = ConnectionDiagram(roots: roots, collapsed: [hub.id, roots[2].id])
        try check(collapsed.nodes.contains { $0.id == hub.id }, "Collapsed parent must remain visible")
        try check(!collapsed.nodes.contains { hidden.contains($0.id) }, "Collapsed descendants must not appear")
        try check(!collapsed.connections.contains { $0.parentID == hub.id || hidden.contains($0.parentID) }, "Hidden outgoing paths must not appear")
        try check(collapsed.size.height < full.size.height, "Collapsing must reclaim layout space")
        let visibleIDs = Set(collapsed.nodes.map(\.id))
        try check(collapsed.connections.flatMap(\.targets).allSatisfy { visibleIDs.contains($0.childID) }, "No path may target a hidden card")
    }

    public static func testDiagramRoutesOutsideCardsAndWithinBounds() throws {
        let variants: [Set<String>] = [[], Set(crowdedRoots.map(\.id))]
        for collapsed in variants {
            let diagram = ConnectionDiagram(roots: crowdedRoots, collapsed: collapsed)
            let canvas = CGRect(origin: .zero, size: diagram.size)
            let cards = diagram.nodes.map { node in
                (node.id, CGRect(x: node.center.x - ConnectionDiagram.cardWidth / 2,
                                 y: node.center.y - ConnectionDiagram.cardHeight / 2,
                                 width: ConnectionDiagram.cardWidth, height: ConnectionDiagram.cardHeight))
            }
            for (index, card) in cards.enumerated() {
                try check(canvas.contains(card.1), "Card \(card.0) must fit inside the canvas")
                for other in cards.dropFirst(index + 1) {
                    try check(!card.1.intersects(other.1), "Cards \(card.0) and \(other.0) must not overlap")
                }
            }
            for section in diagram.sections {
                try check(canvas.contains(section.bounds), "Section bounds must fit inside the canvas")
                try check(canvas.contains(section.labelPoint), "Section label must fit inside the canvas")
                let sectionIDs = Set(diagram.nodes.filter { $0.transport == section.transport }.map(\.id))
                for card in cards where sectionIDs.contains(card.0) {
                    try check(section.bounds.contains(card.1), "A transport card must stay inside its own section")
                }
            }
            for connection in diagram.connections {
                try check(connection.trunkX > connection.source.x, "Trunk belongs in the inter-column gutter")
                let bottom = connection.targets.map { $0.point.y }.max()!
                let segments: [(CGPoint, CGPoint)] = [
                    (connection.source, CGPoint(x: connection.trunkX, y: connection.source.y)),
                    (CGPoint(x: connection.trunkX, y: connection.source.y), CGPoint(x: connection.trunkX, y: bottom))
                ] + connection.targets.map { (CGPoint(x: connection.trunkX, y: $0.point.y), $0.point) }
                for target in connection.targets {
                    try check(connection.trunkX < target.point.x, "Trunk must stop before child cards")
                    try check(target.point.y >= connection.source.y, "Top-aligned branches must route downwards")
                }
                for segment in segments {
                    try check(canvas.contains(segment.0) && canvas.contains(segment.1), "Wire endpoints must fit inside the canvas")
                    for (_, card) in cards {
                        try check(!segmentEnters(segment, rect: card.insetBy(dx: 0.1, dy: 0.1)), "A wire must never pass through a card")
                    }
                }
            }
        }
    }

    public static func testDiagramUsesOneSharedTrunkPerParent() throws {
        let roots = crowdedRoots
        let diagram = ConnectionDiagram(roots: roots, collapsed: [])
        try check(Set(diagram.connections.map(\.parentID)).count == diagram.connections.count,
                  "Multiple siblings must share a single parent connection")
        let usb = diagram.connections.first { $0.parentID == "portlens:mac:usb" }
        try check(usb?.targets.count == 7, "The seven USB buses must share one junction")
        let thunderbolt = diagram.connections.first { $0.parentID == "portlens:mac:thunderbolt" }
        try check(thunderbolt?.targets.count == 3, "The three Thunderbolt buses must share one junction")
        let hub = diagram.connections.first { $0.parentID == "usb:hub:main" }
        try check(hub?.targets.count == 3, "Nested hubs also use a shared junction")
        let actualEdges = Set(diagram.connections.flatMap { connection in connection.targets.map { "\(connection.parentID)>\($0.childID)" } })
        var expectedEdges = Set<String>()
        for root in roots {
            expectedEdges.insert("portlens:mac:\(root.transport.rawValue)>\(root.id)")
            for parent in root.flattened {
                for child in parent.children { expectedEdges.insert("\(parent.id)>\(child.id)") }
            }
        }
        try check(actualEdges == expectedEdges, "Shared geometry must preserve every OS parent-child relationship")
    }

    public static func testDiagramHandlesEmptyAndFilteredTrees() throws {
        let empty = ConnectionDiagram(roots: [], collapsed: [])
        try check(empty.nodes.isEmpty && empty.connections.isEmpty && empty.sections.isEmpty, "Empty results must not invent a connection")
        try check(empty.size.width > 0 && empty.size.height > 0, "Empty canvas dimensions must remain valid")
        let emptyBus = crowdedRoots[6]
        let filtered = ConnectionDiagram(roots: [emptyBus], collapsed: [])
        try check(filtered.nodes.count == 2 && filtered.connections.count == 1, "An empty bus remains visible with its Mac anchor")
        try check(filtered.sections.count == 1 && filtered.sections[0].transport == .usb, "Filtering must not leave an empty second section")
        let mac = filtered.nodes.first { $0.device == nil }!
        let bus = filtered.nodes.first { $0.id == emptyBus.id }!
        try check(mac.center.y == bus.center.y, "A single branch stays horizontal and top-aligned")
        let thunderboltBus = crowdedRoots.last!
        let thunderboltOnly = ConnectionDiagram(roots: [thunderboltBus], collapsed: [])
        try check(thunderboltOnly.sections.map(\.transport) == [.thunderbolt], "A Thunderbolt filter must omit the USB section")
        let thunderboltMac = thunderboltOnly.nodes.first { $0.device == nil }!
        try check(thunderboltMac.center == mac.center, "A single transport must start at the canvas origin without space for a missing section")
        try check(thunderboltOnly.size == filtered.size, "Equivalent single-bus layouts should use the same canvas size")
    }

    /// Synthetic large setup; no actual device identifiers are copied into tests.
    public static var crowdedRoots: [DeviceNode] {
        let nested = DeviceNode(id: "usb:hub:nested", name: "Nested Hub", transport: .usb, kind: .hub, children: [
            DeviceNode(id: "usb:keyboard", name: "Keyboard", transport: .usb, kind: .device),
            DeviceNode(id: "usb:receiver", name: "Receiver", transport: .usb, kind: .device)
        ])
        let hub = DeviceNode(id: "usb:hub:main", name: "USB Hub", transport: .usb, kind: .hub, children: [
            DeviceNode(id: "usb:audio", name: "Audio", transport: .usb, kind: .device), nested,
            DeviceNode(id: "usb:license", name: "License", transport: .usb, kind: .device)
        ])
        let usb = (0..<7).map { index in
            DeviceNode(id: "usb:bus:\(index)", name: "USB バス \(index + 1)", transport: .usb, kind: .bus,
                       children: index == 0 ? [hub] : (index == 6 ? [] : [
                        DeviceNode(id: "usb:device:\(index)", name: "USB Device \(index)", transport: .usb, kind: .device)
                       ]))
        }
        let tb = (0..<3).map { index in
            DeviceNode(id: "tb:bus:\(index)", name: "Thunderbolt / USB4 バス \(index)", transport: .thunderbolt, kind: .bus,
                       children: index == 2 ? [] : [
                        DeviceNode(id: "tb:dock:\(index)", name: "Dock \(index)", transport: .thunderbolt, kind: .device, children: [
                            DeviceNode(id: "tb:display:\(index)", name: "Display \(index)", transport: .thunderbolt, kind: .device)
                        ])
                       ])
        }
        return usb + tb
    }
}

private struct DiagramValidationFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw DiagramValidationFailure(description: message) }
}

private func segmentEnters(_ segment: (CGPoint, CGPoint), rect: CGRect) -> Bool {
    if segment.0.x == segment.1.x {
        return rect.minX < segment.0.x && segment.0.x < rect.maxX &&
            max(segment.0.y, segment.1.y) > rect.minY && min(segment.0.y, segment.1.y) < rect.maxY
    }
    return rect.minY < segment.0.y && segment.0.y < rect.maxY &&
        max(segment.0.x, segment.1.x) > rect.minX && min(segment.0.x, segment.1.x) < rect.maxX
}
