import SwiftUI

struct PremiumBlurOverlay: ViewModifier {
    let isPremium: Bool
    var onUpgrade: () -> Void

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: isPremium ? 0 : 6)
                .allowsHitTesting(isPremium)

            if !isPremium {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.title3)
                                .foregroundStyle(ThemeManager.accentColor)
                            Text(String(localized: "Premium 功能"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                            Button(action: onUpgrade) {
                                Text(String(localized: "升級查看"))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(ThemeManager.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPremium)
    }
}

extension View {
    func premiumBlur(isPremium: Bool, onUpgrade: @escaping () -> Void) -> some View {
        modifier(PremiumBlurOverlay(isPremium: isPremium, onUpgrade: onUpgrade))
    }
}
