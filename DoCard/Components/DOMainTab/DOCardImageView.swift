import SwiftUI

/// DO Card image — the visual centerpiece of the main tab.
/// Shows the physical DO Card with a subtle orange glow.
struct DOCardImageView: View {
  @EnvironmentObject var themeManager: ThemeManager

  var body: some View {
    Image("DOCardMain")
      .resizable()
      .aspectRatio(1.585, contentMode: .fit)
      .frame(maxWidth: 300)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      // Layered orange glow — soft outer + tighter inner
      .shadow(color: themeManager.themeColor.opacity(0.35), radius: 40, x: 0, y: 0)
      .shadow(color: themeManager.themeColor.opacity(0.25), radius: 20, x: 0, y: 0)
      .shadow(color: themeManager.themeColor.opacity(0.15), radius: 8, x: 0, y: 0)
      .frame(maxWidth: .infinity)
  }
}

#Preview {
  DOCardImageView()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
    .environmentObject(ThemeManager.shared)
    .preferredColorScheme(.dark)
}
