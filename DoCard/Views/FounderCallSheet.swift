import SwiftUI

struct FounderCallSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var themeManager: ThemeManager
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private let bookingURL = URL(string: "https://calendly.com/studykenny0210/do-card-1")!

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.white.opacity(0.8))
              .frame(width: 30, height: 30)
              .background(.white.opacity(0.08), in: Circle())
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(String(localized: "關閉"))
        }

        Text(String(localized: "直接打給創辦人"))
          .font(.title2.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.bottom, 14)

        VStack(alignment: .leading, spacing: 7) {
          Text(String(localized: "如果你"))
            .padding(.bottom, 1)
          Text(verbatim: "•  " + String(localized: "遇到bug"))
          Text(verbatim: "•  " + String(localized: "有想要的功能"))
          Text(verbatim: "•  " + String(localized: "任何抱怨"))
          Text(String(localized: "都可以直接打過來！"))
            .padding(.top, 5)
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.7))
        .fixedSize(horizontal: false, vertical: true)

        Text(String(localized: "與 Chen 通話・15 分鐘・線上"))
          .font(.footnote)
          .foregroundStyle(.white.opacity(0.55))
          .padding(.top, 24)
          .padding(.bottom, 14)

        Link(destination: bookingURL) {
          Text(String(localized: "預約通話"))
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay(alignment: .trailing) {
              Image(systemName: "arrow.right")
                .font(.system(size: 16, weight: .medium))
                .padding(.trailing, 16)
                .accessibilityHidden(true)
            }
            .foregroundStyle(.black)
            .background(themeManager.themeColor, in: RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityHint(String(localized: "開啟 Calendly 預約頁面"))
        .accessibilityIdentifier("contact.bookCall")
      }
      .padding(.horizontal, 24)
      .padding(.top, 12)
      .padding(.bottom, 24)
    }
    .scrollBounceBehavior(.basedOnSize)
    .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(430)])
    .presentationDragIndicator(.visible)
    .presentationCornerRadius(28)
    .presentationBackground(Color(white: 0.09))
    .preferredColorScheme(.dark)
  }
}

#Preview {
  FounderCallSheet()
    .environmentObject(ThemeManager.shared)
}
