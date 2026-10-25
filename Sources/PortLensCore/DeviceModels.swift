import Foundation

public enum DeviceTransport: String, Codable, CaseIterable, Sendable {
    case usb
    case thunderbolt
}

public enum DeviceKind: String, Codable, Sendable {
    case bus
    case hub
    case device
}

public struct DeviceProperty: Codable, Hashable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// An OS-reported connection node, not necessarily a separate physical product.
public struct DeviceNode: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let vendor: String?
    public let transport: DeviceTransport
    public let kind: DeviceKind
    public let speed: String?
    public let locationID: String?
    public let properties: [DeviceProperty]
    public let children: [DeviceNode]

    public init(
        id: String,
        name: String,
        vendor: String? = nil,
        transport: DeviceTransport,
        kind: DeviceKind,
        speed: String? = nil,
        locationID: String? = nil,
        properties: [DeviceProperty] = [],
        children: [DeviceNode] = []
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.transport = transport
        self.kind = kind
        self.speed = speed
        self.locationID = locationID
        self.properties = properties
        self.children = children
    }

    public var flattened: [DeviceNode] {
        [self] + children.flatMap(\.flattened)
    }
}

public struct DeviceSnapshot: Codable, Sendable {
    public let capturedAt: Date
    public let usbBuses: [DeviceNode]
    public let thunderboltBuses: [DeviceNode]
    public let warnings: [String]

    public init(
        capturedAt: Date = Date(),
        usbBuses: [DeviceNode],
        thunderboltBuses: [DeviceNode],
        warnings: [String] = []
    ) {
        self.capturedAt = capturedAt
        self.usbBuses = usbBuses
        self.thunderboltBuses = thunderboltBuses
        self.warnings = warnings
    }

    public var allNodes: [DeviceNode] {
        (usbBuses + thunderboltBuses).flatMap(\.flattened)
    }

    /// Entirely synthetic data. No actual host or user identifiers are included.
    public static var demo: DeviceSnapshot {
        DeviceSnapshot(
            usbBuses: [
                DeviceNode(id: "demo:usb:bus", name: "USB バス", transport: .usb, kind: .bus,
                           children: [
                            DeviceNode(id: "demo:usb:hub", name: "デスクの USB ハブ", vendor: "Demo", transport: .usb, kind: .hub, speed: "5 Gb/s", children: [
                                DeviceNode(id: "demo:usb:audio", name: "Audio Interface", vendor: "Demo Audio", transport: .usb, kind: .device, speed: "480 Mb/s", locationID: "0x00110000"),
                                DeviceNode(id: "demo:usb:keyboard", name: "Keyboard", vendor: "Demo", transport: .usb, kind: .device, speed: "12 Mb/s", locationID: "0x00120000"),
                                DeviceNode(id: "demo:usb:controller", name: "DAW Controller", vendor: "Demo Audio", transport: .usb, kind: .device, speed: "12 Mb/s", locationID: "0x00130000")
                            ])
                           ])
            ],
            thunderboltBuses: [
                DeviceNode(id: "demo:tb:bus", name: "Thunderbolt / USB4 バス 0", transport: .thunderbolt, kind: .bus, children: [
                    DeviceNode(id: "demo:tb:dock", name: "Thunderbolt Dock", vendor: "Demo", transport: .thunderbolt, kind: .device, speed: "最大 40 Gb/s", children: [
                        DeviceNode(id: "demo:tb:display", name: "Display", vendor: "Demo", transport: .thunderbolt, kind: .device, speed: "最大 40 Gb/s")
                    ])
                ])
            ]
        )
    }
}
