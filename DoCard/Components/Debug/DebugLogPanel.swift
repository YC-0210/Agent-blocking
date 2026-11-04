#if DEBUG
import SwiftUI
import UIKit

struct DebugLogPanel: View {
  var diagnostics: () -> String = { "" }

  @State private var logText: String = ""
  @State private var sizeBytes: Int = 0

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
      .buttonStyle(.borderless)

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
  }

  private func load() {
    logText = diagnostics() + DebugLogStore.readAll()
    sizeBytes = DebugLogStore.sizeBytes()
  }
}

#Preview {
  DebugLogPanel()
    .padding()
}
#endif
