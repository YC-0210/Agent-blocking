import StoreKit
import SwiftUI

// MARK: - Feature Item Model

private struct FeatureItem {
    let icon: String
    let title: String
    let detail: String
}

// MARK: - Plan Option

private enum PlanOption {
    case monthly, annual
}

// MARK: - PremiumUpgradeView

struct PremiumUpgradeView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: PlanOption = .annual

    private let features: [FeatureItem] = [
        FeatureItem(icon: "square.stack.fill",       title: String(localized: "阻擋最多 50 個 App"),      detail: String(localized: "最多 50 個")),
        FeatureItem(icon: "clock.fill",              title: String(localized: "排程自動化"),          detail: String(localized: "固定時段自動啟動")),
        FeatureItem(icon: "chart.line.uptrend.xyaxis", title: "深度 Focus Report",                 detail: String(localized: "習慣曲線 & 趨勢")),
        FeatureItem(icon: "star.fill",               title: String(localized: "專注分數 & 週報"),    detail: String(localized: "看見你的成長")),
        FeatureItem(icon: "laptopcomputer.and.iphone", title: String(localized: "Chrome 連動"),       detail: String(localized: "刷卡時同步封鎖 Chrome 上的網站")),
    ]

    private var selectedProduct: Product? {
        switch selectedPlan {
        case .monthly: return subscriptionManager.monthlyProduct
        case .annual:  return subscriptionManager.annualProduct
        }
    }

    private var hasTrialOffer: Bool {
        guard let product = selectedProduct else { return false }
        return product.subscription?.introductoryOffer?.paymentMode == .freeTrial
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    headerBadge
                    titleSection
                    planSelector
                    featureList
                    ctaButton
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .background(Color(hex: "#0D0D0D").ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                }
            }
        }
        .task {
            if subscriptionManager.products.isEmpty {
                await subscriptionManager.loadProducts()
            }
        }
        .alert(
            String(localized: "提示"),
            isPresented: Binding(
                get: { subscriptionManager.errorMessage != nil },
                set: { if !$0 { subscriptionManager.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "好"), role: .cancel) {}
        } message: {
            Text(subscriptionManager.errorMessage ?? "")
        }
        .onChange(of: subscriptionManager.tier) { _, newTier in
            if newTier == .premium { dismiss() }
        }
    }

    // MARK: - Header Badge

    private var headerBadge: some View {
        Text("✦ DO CARD PREMIUM")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(ThemeManager.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(ThemeManager.accentColor.opacity(0.15))
                    .overlay(
                        Capsule()
                            .stroke(ThemeManager.accentColor.opacity(0.35), lineWidth: 1)
                    )
            )
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(spacing: 10) {
            Text(String(localized: "解鎖完整專注力"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(String(localized: "升級 Premium，讓每次輕觸都創造更深的儀式感"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }

    // MARK: - Plan Selector

    private var planSelector: some View {
        HStack(spacing: 12) {
            planCard(
                option: .monthly,
                label: String(localized: "月訂閱"),
                price: subscriptionManager.monthlyProduct?.displayPrice,
                period: String(localized: "/ 月"),
                savingsBadge: nil
            )
            planCard(
                option: .annual,
                label: String(localized: "年訂閱"),
                price: subscriptionManager.annualProduct?.displayPrice,
                period: String(localized: "/ 年・NT$65/月"),
                savingsBadge: String(localized: "省 $398")
            )
        }
    }

    private func planCard(
        option: PlanOption,
        label: String,
        price: String?,
        period: String,
        savingsBadge: String?
    ) -> some View {
        let isSelected = selectedPlan == option

        return Button(action: { selectedPlan = option }) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.5))

                    if let price {
                        Text(price)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(isSelected ? ThemeManager.accentColor : .white)
                    } else {
                        ProgressView()
                            .tint(ThemeManager.accentColor)
                            .padding(.vertical, 4)
                    }

                    Text(period)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.6) : .white.opacity(0.3))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected
                            ? ThemeManager.accentColor.opacity(0.1)
                            : Color.white.opacity(0.05)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    isSelected
                                        ? ThemeManager.accentColor
                                        : Color.white.opacity(0.1),
                                    lineWidth: isSelected ? 1.5 : 1
                                )
                        )
                )

                if let badge = savingsBadge {
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(ThemeManager.accentColor))
                        .offset(x: -10, y: -10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(spacing: 0) {
            Text("PREMIUM 功能")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, item in
                    featureRow(item)

                    if index < features.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    private func featureRow(_ item: FeatureItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ThemeManager.accentColor.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ThemeManager.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(ThemeManager.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        Button(action: {
            guard let product = selectedProduct else { return }
            Task { await subscriptionManager.purchase(product) }
        }) {
            HStack(spacing: 8) {
                if subscriptionManager.purchaseInProgress {
                    ProgressView().tint(.white)
                } else {
                    Text(hasTrialOffer
                        ? String(localized: "開始免費試用")
                        : String(localized: "立即升級"))
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        subscriptionManager.purchaseInProgress || selectedProduct == nil
                            ? ThemeManager.accentColor.opacity(0.4)
                            : ThemeManager.accentColor
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.purchaseInProgress || selectedProduct == nil)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: {
                Task { await subscriptionManager.restorePurchases() }
            }) {
                Text(String(localized: "恢復購買"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text(String(localized: "訂閱將自動續費，可隨時在設定中取消"))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.22))
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Link(
                    String(localized: "隱私權政策"),
                    destination: URL(string: "https://do-card.online/privacy")!
                )
                Text("·")
                    .foregroundStyle(.white.opacity(0.22))
                Link(
                    String(localized: "服務條款"),
                    destination: URL(string: "https://do-card.online/terms")!
                )
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.32))
        }
    }
}

// MARK: - Preview

#Preview {
    PremiumUpgradeView()
        .environmentObject(SubscriptionManager.shared)
}
