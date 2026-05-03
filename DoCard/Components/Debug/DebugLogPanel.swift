#if DEBUG
import SwiftUI
import UIKit

struct DebugLogPanel: View {
  @State private var logText: String = ""
  @State private var sizeBytes: Int = 0
  @State private var refreshTick: Int = 0

  private var formattedSize: String {
    let kb = Double(sizeBytes) / 1024.0
    return String(format: "%.1f KB", kb)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Buffer: \(formattedSize)")
          .font(.caption.monospaced())
          .foregroundColor(.secondary)
        Spacer()
        Button("Refresh") {
          load()
        }
        .font(.caption)
        Button("Copy") {
          UIPasteboard.general.string = logText
        }
        .font(.caption)
        Button("Clear") {
          DebugLogStore.clear()
          load()
        }
        .font(.caption)
        .foregroundColor(.red)
      }

      ScrollView {
        Text(logText.isEmpty ? "(empty)" : logText)
          .font(.caption2.monospaced())
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
      .frame(maxHeight: 360)
      .padding(8)
      .background(Color(.systemGray6))
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .onAppear { load() }
    .id(refreshTick)
  }

  private func load() {
    logText = DebugLogStore.readAll()
    sizeBytes = DebugLogStore.sizeBytes()
    refreshTick &+= 1
  }
}

#Preview {
  DebugLogPanel()
    .padding()
}
#endif
