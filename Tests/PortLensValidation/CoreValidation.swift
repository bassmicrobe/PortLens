import Foundation
import PortLensCore

public struct CoreValidationCase {
    public let name: String
    public let run: () throws -> Void
}

public struct CoreValidationResult {
    public let name: String
    public let failure: String?
    public var passed: Bool { failure == nil }
}

/// Shared cases for the Foundation-only runner and the XCTest adapter.
public enum CoreValidation {
    public static var cases: [CoreValidationCase] {
        [
            CoreValidationCase(name: "testPreservesNestedLogicalHubsAndDuplicateDeviceNames", run: testPreservesNestedLogicalHubsAndDuplicateDeviceNames),
            CoreValidationCase(name: "testKeepsEmptyBusesWithoutTreatingThemAsPhysicalFreePorts", run: testKeepsEmptyBusesWithoutTreatingThemAsPhysicalFreePorts),
            CoreValidationCase(name: "testThunderboltHierarchyUsesRoutesAndUpstreamLinkSpeed", run: testThunderboltHierarchyUsesRoutesAndUpstreamLinkSpeed),
            CoreValidationCase(name: "testIdentifiersIgnoreConnectionGenerationAndSiblingOrdering", run: testIdentifiersIgnoreConnectionGenerationAndSiblingOrdering),
            CoreValidationCase(name: "testIdentifierChangesWhenDifferentProductUsesSamePort", run: testIdentifierChangesWhenDifferentProductUsesSamePort),
            CoreValidationCase(name: "testExportExcludesSensitiveAndUnknownSourceFields", run: testExportExcludesSensitiveAndUnknownSourceFields),
            CoreValidationCase(name: "testMissingTransportProducesWarningAndInvalidSchemaThrows", run: testMissingTransportProducesWarningAndInvalidSchemaThrows),
            CoreValidationCase(name: "testCapturesTimestampAndSyntheticDemoHasUniqueIdentifiers", run: testCapturesTimestampAndSyntheticDemoHasUniqueIdentifiers)
        ] + GraphValidation.cases + ZoomValidation.cases
    }

    public static func runAll() -> [CoreValidationResult] {
        cases.map { test in
            do {
                try test.run()
                return CoreValidationResult(name: test.name, failure: nil)
            } catch {
                return CoreValidationResult(name: test.name, failure: String(describing: error))
            }
        }
    }

    public static func testPreservesNestedLogicalHubsAndDuplicateDeviceNames() throws {
        let snapshot = try DeviceCollector.parse(Data(Self.fixture.utf8))
        let usb = snapshot.usbBuses.flatMap(\.flattened)
        let licenses = usb.filter { $0.name == "iLok" }
        try expectEqual(licenses.count, 2)
        try expectNotEqual(licenses[0].id, licenses[1].id)
        try expectEqual(licenses.map(\.locationID), ["0x00110000", "0x00121000"])
        try expectEqual(usb.filter { $0.kind == .hub }.count, 2)
        try expectEqual(snapshot.usbBuses[0].children[0].name, "USB 2.0 Hub")
        try expectEqual(snapshot.usbBuses[0].children[0].vendor, "Example Vendor")
        try expectEqual(snapshot.usbBuses[0].children[0].children[1].children[0].name, "iLok")
        try expectEqual(licenses.first?.speed, "12 Mb/s")
    }

    public static func testKeepsEmptyBusesWithoutTreatingThemAsPhysicalFreePorts() throws {
        let snapshot = try DeviceCollector.parse(Data(Self.fixture.utf8))
        try expectEqual(snapshot.usbBuses.count, 2)
        try expect(snapshot.usbBuses[1].children.isEmpty)
        try expectEqual(snapshot.usbBuses[1].kind, .bus)
        try expectEqual(snapshot.thunderboltBuses.count, 2)
        try expect(snapshot.thunderboltBuses[1].children.isEmpty)
        try expectFalse(snapshot.allNodes.contains { $0.name.contains("空きポート") })
    }

    public static func testThunderboltHierarchyUsesRoutesAndUpstreamLinkSpeed() throws {
        let snapshot = try DeviceCollector.parse(Data(Self.fixture.utf8))
        let dock = try unwrap(snapshot.thunderboltBuses.first?.children.first)
        try expectEqual(dock.name, "Example Dock")
        try expectEqual(dock.speed, "最大 40 Gb/s x1")
        try expectEqual(dock.locationID, "1")
        try expectEqual(dock.children.first?.name, "Example Display")
        try expectEqual(dock.children.first?.locationID, "101")
        try expectEqual(dock.children.first?.transport, .thunderbolt)
        try expectEqual(dock.properties.first { $0.label == "接続方式" }?.value, "USB4")
    }

    public static func testIdentifiersIgnoreConnectionGenerationAndSiblingOrdering() throws {
        let first = try DeviceCollector.parse(Data(Self.fixture.utf8))
        var changed = try unwrap(JSONSerialization.jsonObject(with: Data(Self.fixture.utf8)) as? [String: Any])
        var buses = try unwrap(changed["SPUSBDataType"] as? [[String: Any]])
        var hubs = try unwrap(buses[0]["_items"] as? [[String: Any]])
        var devices = try unwrap(hubs[0]["_items"] as? [[String: Any]])
        devices[0]["location_id"] = "0x00110000 / 99"
        hubs[0]["location_id"] = "0x00100000 / 42"
        hubs[0]["_items"] = devices.reversed().map { $0 }
        buses[0]["_items"] = hubs
        changed["SPUSBDataType"] = buses.reversed().map { $0 }
        let second = try DeviceCollector.parse(JSONSerialization.data(withJSONObject: changed))
        try expectEqual(Set(first.allNodes.map(\.id)), Set(second.allNodes.map(\.id)))
    }

    public static func testIdentifierChangesWhenDifferentProductUsesSamePort() throws {
        let first = try DeviceCollector.parse(Data(Self.fixture.utf8))
        let changed = Self.fixture.replacingOccurrences(of: "0x5036", with: "0x9999")
        let second = try DeviceCollector.parse(Data(changed.utf8))
        let firstIDs = Set(first.allNodes.filter { $0.name == "iLok" }.map(\.id))
        let secondIDs = Set(second.allNodes.filter { $0.name == "iLok" }.map(\.id))
        try expect(firstIDs.isDisjoint(with: secondIDs))
    }

    public static func testExportExcludesSensitiveAndUnknownSourceFields() throws {
        let snapshot = try DeviceCollector.parse(Data(Self.fixture.utf8))
        let encoded = try JSONEncoder().encode(snapshot)
        let text = try unwrap(String(data: encoded, encoding: .utf8))
        for excluded in ["SECRET_SERIAL", "SECRET_SWITCH_UID", "SECRET_DOMAIN_UUID", "SECRET_CABLE_SERIAL", "SECRET_MAC", "SECRET_EXTRA"] {
            try expectFalse(text.contains(excluded), "Unexpected private field: \(excluded)")
        }
        let decoded = try JSONDecoder().decode(DeviceSnapshot.self, from: encoded)
        try expectEqual(snapshot.allNodes, decoded.allNodes)
    }

    public static func testMissingTransportProducesWarningAndInvalidSchemaThrows() throws {
        let partial = try DeviceCollector.parse(Data(#"{"SPUSBDataType":[]}"#.utf8))
        try expectEqual(partial.warnings.count, 1)
        try expect(partial.thunderboltBuses.isEmpty)
        for document in ["{}", "[]", #"{"SPUSBDataType":{}}"#, #"{"SPUSBDataType":[{"_items":"bad"}]}"#] {
            try expectCollectionError(.invalidSchema) {
                _ = try DeviceCollector.parse(Data(document.utf8))
            }
        }
        try expectCollectionError(.invalidJSON) {
            _ = try DeviceCollector.parse(Data("invalid".utf8))
        }
    }

    public static func testCapturesTimestampAndSyntheticDemoHasUniqueIdentifiers() throws {
        let date = Date(timeIntervalSince1970: 123456)
        let snapshot = try DeviceCollector.parse(Data(Self.fixture.utf8), capturedAt: date)
        try expectEqual(snapshot.capturedAt, date)
        let demo = DeviceSnapshot.demo
        try expectFalse(demo.usbBuses.isEmpty)
        try expectFalse(demo.thunderboltBuses.isEmpty)
        try expectEqual(Set(demo.allNodes.map(\.id)).count, demo.allNodes.count)
    }

}

private struct ValidationFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Assertion failed", file: StaticString = #fileID, line: UInt = #line) throws {
    guard condition() else { throw ValidationFailure(description: "\(file):\(line): \(message)") }
}

private func expectFalse(_ condition: @autoclosure () -> Bool, _ message: String = "Expected false", file: StaticString = #fileID, line: UInt = #line) throws {
    try expect(!condition(), message, file: file, line: line)
}

private func expectEqual<Value: Equatable>(_ actual: Value, _ expected: Value, file: StaticString = #fileID, line: UInt = #line) throws {
    guard actual == expected else {
        throw ValidationFailure(description: "\(file):\(line): Expected \(expected), got \(actual)")
    }
}

private func expectNotEqual<Value: Equatable>(_ actual: Value, _ other: Value, file: StaticString = #fileID, line: UInt = #line) throws {
    guard actual != other else {
        throw ValidationFailure(description: "\(file):\(line): Expected distinct values, got \(actual)")
    }
}

private func unwrap<Value>(_ value: Value?, file: StaticString = #fileID, line: UInt = #line) throws -> Value {
    guard let value else { throw ValidationFailure(description: "\(file):\(line): Expected a non-nil value") }
    return value
}

private func expectCollectionError(_ expected: DeviceCollectionError, file: StaticString = #fileID, line: UInt = #line, operation: () throws -> Void) throws {
    do {
        try operation()
    } catch {
        try expectEqual(error as? DeviceCollectionError, expected, file: file, line: line)
        return
    }
    throw ValidationFailure(description: "\(file):\(line): Expected error \(expected), but operation succeeded")
}
