import SwiftUI

struct LicensesView: View {
  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text("Foqos")
            .font(.headline)
          Text("By Ali Waseem")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text(String(localized: "Licensed under the MIT License."))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      }
    }
    .navigationTitle(String(localized: "Licenses"))
  }
}

#Preview {
  NavigationStack {
    LicensesView()
  }
}
