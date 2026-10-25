import AppKit
import SwiftUI
import PortLensCore

@main
enum PortLensLauncher {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--help") {
            print("""
            PortLens — Macのつながりを、ひと目で。
            Usage: PortLens [--demo] [--snapshot]
              --demo      サンプルデータで表示（機器の読み取りなし）
              --snapshot  USB・Thunderboltの認識状態をJSONで標準出力
            """)
            return
        }
        if CommandLine.arguments.contains("--snapshot") {
            Task {
                do {
                    let snapshot: DeviceSnapshot
                    if CommandLine.arguments.contains("--demo") {
                        snapshot = .demo
                    } else {
                        snapshot = try await DeviceCollector.collect()
                    }
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    encoder.dateEncodingStrategy = .iso8601
                    FileHandle.standardOutput.write(try encoder.encode(snapshot))
                    FileHandle.standardOutput.write(Data("\n".utf8))
                    exit(EXIT_SUCCESS)
                } catch {
                    FileHandle.standardError.write(Data("PortLens: \(error.localizedDescription)\n".utf8))
                    exit(EXIT_FAILURE)
                }
            }
            dispatchMain()
        }
        PortLensApplication.main()
    }
}

struct PortLensApplication: App {
    @StateObject private var model = AppModel(isDemo: CommandLine.arguments.contains("--demo"))

    var body: some Scene {
        Window("PortLens", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 1040, minHeight: 660)
                .task { await model.refresh() }
                .task(id: model.autoRefresh) {
                    guard model.autoRefresh else { return }
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(10)) } catch { return }
                        guard !Task.isCancelled else { return }
                        await model.refresh()
                    }
                }
        }
        .defaultSize(width: 1380, height: 860)
        .commands {
            CommandGroup(after: .newItem) {
                Button("接続情報を更新") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isLoading)
                Button("JSONを書き出す…") { model.exportSnapshot() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.snapshot == nil)
            }
            CommandGroup(after: .sidebar) {
                Button("詳細パネルを切り替える") { model.showInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(model.selectedNode == nil)
            }
        }
    }
}
