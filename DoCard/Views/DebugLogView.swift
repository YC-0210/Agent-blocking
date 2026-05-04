#if DEBUG
import SwiftUI
import UIKit

/// Standalone log viewer — has zero dependencies on StrategyManager, modelContext,
/// or any other env object. Safe to present from any view without setup. Used as
/// the temporary entry point from SettingsTabView's Debug row.
struct DebugLogView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var logText: String = ""
  @State private var sizeBytes: Int = 0
  @State private var copyToastShown = false

  private var formattedSize: String {
    let kb = Double(sizeBytes) / 1024.0
    return String(format: "%.1f KB", kb)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Toolbar row
        HStack(spacing: 12) {
          Text("\(formattedSize) · \(logText.count) chars")
            .font(.caption.monospaced())
            .foregroundColor(.secondary)
          Spacer()
          Button("Refresh") { load() }
            .font(.caption)
          Button("Clear") {
            DebugLogStore.clear()
            load()
          }
          .font(.caption)
          .foregroundColor(.red)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)

        // Log content
        ScrollView {
          Text(logText.isEmpty ? "(empty — go test something then come back)" : logText)
            .font(.caption2.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(8)
        }
        .background(Color(.systemGray6))

        // Big copy button
        Button(action: copyAll) {
          HStack {
            Image(systemName: "doc.on.doc.fill")
            Text("複製全部 Log")
              .font(.headline)
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(Color.accentColor)
          .foregroundColor(.white)
          .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
      }
      .navigationTitle("Debug Log")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("關閉") { dismiss() }
        }
      }
      .alert("已複製", isPresented: $copyToastShown) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("\(logText.count) 個字元已放到剪貼簿")
      }
      .onAppear { load() }
    }
  }

  private func load() {
    logText = DebugLogStore.readAll()
    sizeBytes = DebugLogStore.sizeBytes()
  }

  private func copyAll() {
    UIPasteboard.general.string = logText
    copyToastShown = true
  }
}

#Preview {
  DebugLogView()
}
#endif
