import Foundation
import Darwin

public enum DeviceCollectionError: LocalizedError, Equatable {
    case unavailable
    case timedOut
    case processFailed(Int32)
    case invalidJSON
    case invalidSchema

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "macOS の接続情報を取得できませんでした。system_profiler を実行できる環境か確認してください。"
        case .timedOut:
            return "接続情報の取得がタイムアウトしました。少し待ってから再度更新してください。"
        case .processFailed(let status):
            return "macOS の情報取得が終了コード \(status) で失敗しました。再度更新してください。"
        case .invalidJSON:
            return "macOS から返された接続情報を読み取れませんでした。"
        case .invalidSchema:
            return "対応する USB / Thunderbolt の接続情報が見つかりませんでした。"
        }
    }
}

public enum DeviceCollector {
    public static func collect() async throws -> DeviceSnapshot {
        // Process startup and pipe reads never block the UI actor.
        let data = try await Task.detached(priority: .utility) {
            try readSystemProfiler()
        }.value
        return try parse(data)
    }

    public static func parse(_ data: Data, capturedAt: Date = Date()) throws -> DeviceSnapshot {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DeviceCollectionError.invalidJSON
        }
        guard let document = object as? [String: Any],
              document["SPUSBDataType"] != nil || document["SPThunderboltDataType"] != nil else {
            throw DeviceCollectionError.invalidSchema
        }
        var warnings: [String] = []
        let usb = try entries(document, key: "SPUSBDataType", warnings: &warnings)
        let thunderbolt = try entries(document, key: "SPThunderboltDataType", warnings: &warnings)
        var occurrences: [String: Int] = [:]
        let usbBuses = try usb.enumerated().map { index, raw -> DeviceNode in
            let controller = string(raw, "host_controller") ?? "USB"
            let childLocations = (raw["_items"] as? [[String: Any]] ?? []).compactMap { location($0) }
            // USB location IDs contain the host bus in their high byte. Ignore the
            // connection-generation address following the slash in profiler output.
            let busLocation = childLocations.sorted().first.map { String($0.prefix(4)) }
            let base = "usb:bus:\(controller):\(busLocation ?? "empty")"
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            let id = occurrence == 0 ? base : "\(base):\(occurrence)"
            var properties = [DeviceProperty(label: "ホストコントローラー", value: controller)]
            if let osName = string(raw, "_name") {
                properties.append(DeviceProperty(label: "OS のバス名", value: osName))
            }
            return DeviceNode(id: id, name: "USB バス \(index + 1)", transport: .usb, kind: .bus,
                              properties: properties,
                              children: try usbChildren(raw, parentID: id))
        }
        let thunderboltBuses = try thunderbolt.enumerated().map { index, raw -> DeviceNode in
            let osName = string(raw, "_name") ?? "bus_\(index)"
            let id = "thunderbolt:bus:\(osName)"
            let suffix = osName.split(separator: "_").last.map(String.init) ?? String(index)
            return DeviceNode(id: id, name: "Thunderbolt / USB4 バス \(suffix)", transport: .thunderbolt,
                              kind: .bus, properties: [DeviceProperty(label: "OS のバス名", value: osName)],
                              children: try thunderboltChildren(raw, parentID: id, busID: id))
        }
        return DeviceSnapshot(capturedAt: capturedAt, usbBuses: usbBuses,
                              thunderboltBuses: thunderboltBuses, warnings: warnings)
    }

    private static func entries(_ raw: [String: Any], key: String, warnings: inout [String]) throws -> [[String: Any]] {
        guard let value = raw[key] else {
            warnings.append(key == "SPUSBDataType" ? "USB の情報が返されませんでした。" : "Thunderbolt / USB4 の情報が返されませんでした。")
            return []
        }
        guard let result = value as? [[String: Any]] else {
            throw DeviceCollectionError.invalidSchema
        }
        return result
    }

    private static func children(_ raw: [String: Any]) throws -> [[String: Any]] {
        guard let value = raw["_items"] else { return [] }
        guard let result = value as? [[String: Any]] else {
            throw DeviceCollectionError.invalidSchema
        }
        return result
    }

    private static func usbChildren(_ raw: [String: Any], parentID: String) throws -> [DeviceNode] {
        var occurrences: [String: Int] = [:]
        return try children(raw).map { child in
            let name = string(child, "_name") ?? "名前不明の USB 機器"
            let locationID = location(child)
            let vendorID = string(child, "vendor_id")?.split(separator: " ").first.map(String.init) ?? "unknown"
            let productID = string(child, "product_id") ?? "unknown"
            let base = locationID.map { "usb:\($0):\(vendorID):\(productID)" }
                ?? "\(parentID)/\(vendorID):\(productID):\(name)"
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            let id = occurrence == 0 ? base : "\(base):\(occurrence)"
            let kind: DeviceKind = name.range(of: "hub", options: .caseInsensitive) != nil ? .hub : .device
            let properties = selectedProperties(child, fields: [
                ("vendor_id", "Vendor ID"), ("product_id", "Product ID"),
                ("bcd_device", "デバイスバージョン"), ("bus_power", "利用可能電流（mA・OS申告）"),
                ("bus_power_used", "要求電流（mA・OS申告）")
            ])
            return DeviceNode(id: id, name: name, vendor: string(child, "manufacturer"), transport: .usb,
                              kind: kind, speed: usbSpeed(string(child, "device_speed")), locationID: locationID,
                              properties: properties, children: try usbChildren(child, parentID: id))
        }
    }

    private static func thunderboltChildren(_ raw: [String: Any], parentID: String, busID: String) throws -> [DeviceNode] {
        var occurrences: [String: Int] = [:]
        return try children(raw).map { child in
            let name = string(child, "device_name_key") ?? string(child, "_name") ?? "名前不明の Thunderbolt 機器"
            let route = string(child, "route_string_key")
            let vendor = string(child, "vendor_id_key") ?? "unknown"
            let product = string(child, "device_id_key") ?? "unknown"
            let base = route.map { "\(busID):route:\($0):\(vendor):\(product)" } ?? "\(parentID)/\(vendor):\(product):\(name)"
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            let id = occurrence == 0 ? base : "\(base):\(occurrence)"
            let upstream = child["receptacle_upstream_ambiguous_tag"] as? [String: Any] ?? [:]
            var properties = selectedProperties(child, fields: [
                ("vendor_id_key", "Vendor ID"), ("device_id_key", "Device ID"),
                ("route_string_key", "ルート"), ("switch_version_key", "スイッチバージョン")
            ])
            if let mode = string(child, "mode_key") {
                let label = ["thunderbolt_two": "Thunderbolt 2", "thunderbolt_three": "Thunderbolt 3", "thunderbolt_four": "Thunderbolt 4", "usb_four": "USB4"][mode] ?? mode
                properties.append(DeviceProperty(label: "接続方式", value: label))
            }
            return DeviceNode(id: id, name: name, vendor: string(child, "vendor_name_key"), transport: .thunderbolt,
                              kind: .device, speed: string(upstream, "current_speed_key")?.replacingOccurrences(of: "Up to ", with: "最大 "),
                              locationID: route, properties: properties,
                              children: try thunderboltChildren(child, parentID: id, busID: busID))
        }
    }

    /// Explicit allowlist: serial numbers, switch UIDs, domain UUIDs and MAC
    /// addresses are deliberately never copied into the model or JSON export.
    private static func selectedProperties(_ raw: [String: Any], fields: [(String, String)]) -> [DeviceProperty] {
        fields.compactMap { key, label in
            string(raw, key).map { DeviceProperty(label: label, value: $0) }
        }
    }

    private static func string(_ raw: [String: Any], _ key: String) -> String? {
        let value: String?
        if let text = raw[key] as? String {
            value = text
        } else if let number = raw[key] as? NSNumber {
            value = number.stringValue
        } else {
            value = nil
        }
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func location(_ raw: [String: Any]) -> String? {
        string(raw, "location_id")?.split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func usbSpeed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return ["low_speed": "1.5 Mb/s", "full_speed": "12 Mb/s", "high_speed": "480 Mb/s",
                "super_speed": "5 Gb/s", "super_speed_plus": "SuperSpeed+"][raw] ?? raw
    }

    private static func readSystemProfiler() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPUSBDataType", "SPThunderboltDataType", "-json", "-timeout", "20"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        do { try process.run() } catch { throw DeviceCollectionError.unavailable }

        let output = ProcessOutput()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            output.setData(stdout.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            // Drain stderr independently so a full pipe cannot stall the child.
            // Do not include unfiltered diagnostic output in user exports.
            _ = stderr.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        let timedOut = terminated.wait(timeout: .now() + 35) == .timedOut
        if timedOut {
            process.terminate()
            if terminated.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = terminated.wait(timeout: .now() + 2)
            }
        }
        // system_profiler is a fixed trusted command. Keep even pipe shutdown
        // bounded, in case a child inherited a descriptor unexpectedly.
        let drained = readers.wait(timeout: .now() + 3) == .success
        guard !timedOut, drained else { throw DeviceCollectionError.timedOut }
        guard process.terminationStatus == 0 else {
            throw DeviceCollectionError.processFailed(process.terminationStatus)
        }
        return output.data
    }
}

private final class ProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func setData(_ data: Data) {
        lock.lock()
        stored = data
        lock.unlock()
    }
}
