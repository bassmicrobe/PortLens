import SwiftUI

/// Explicit flexible widths keep macOS sidebar cells from sizing their title
/// to the minimum while the selection background fills the entire row.
struct SidebarRow: View {
    let title: String
    var symbol: String? = nil
    var dotColor: Color? = nil
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(.tint)
                } else {
                    Circle().fill(dotColor ?? .secondary).frame(width: 6, height: 6)
                }
            }
            .frame(width: 18)
            .fixedSize(horizontal: true, vertical: false)

            Text(title)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            if let count {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 20, alignment: .trailing)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
