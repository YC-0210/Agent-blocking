import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("DO Card Premium")
                            .font(.title)
                            .fontWeight(.bold)

                        Text(String(localized: "解鎖所有功能，專注不受限"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    // Feature comparison
                    VStack(spacing: 0) {
                        featureRow(
                            title: String(localized: "App 封鎖數量"),
                            free: String(localized: "3 個"),
                            premium: String(localized: "最多 50 個")
                        )
                        Divider()
                        featureRow(
                            title: String(localized: "類別封鎖"),
                            free: "—",
                            premium: "✓"
                        )
                        Divider()
                        featureRow(
                            title: String(localized: "網域封鎖"),
                            free: "✓",
                            premium: "✓"
                        )
                        Divider()
                        featureRow(
                            title: String(localized: "排程自動化"),
                            free: "—",
                            premium: "✓"
                        )
                        Divider()
                        featureRow(
                            title: String(localized: "DO Card 觸發"),
                            free: "✓",
                            premium: "✓"
                        )
                        Divider()
                        featureRow(
                            title: String(localized: "緊急解鎖"),
                            free: "✓",
                            premium: "✓"
                        )
                        Divider()
                        featureRow(
                            title: String(localized: "進階報告"),
                            free: "—",
                            premium: "✓"
                        )
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .padding(.horizontal, 20)

                    // Purchase buttons
                    VStack(spacing: 12) {
                        if let annual = subscriptionManager.annualProduct {
                            PurchaseButton(
                                product: annual,
                                label: String(localized: "年費方案"),
                                sublabel: annual.displayPrice + " / " + String(localized: "年"),
                                isBestValue: true
                            )
                        }

                        if let monthly = subscriptionManager.monthlyProduct {
                            PurchaseButton(
                                product: monthly,
                                label: String(localized: "月費方案"),
                                sublabel: monthly.displayPrice + " / " + String(localized: "月"),
                                isBestValue: false
                            )
                        }

                        if subscriptionManager.isLoadingProducts {
                            ProgressView()
                                .padding()
                        } else if subscriptionManager.productsLoadFailed {
                            VStack(spacing: 12) {
                                Text(String(localized: "無法載入訂閱方案"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Button(action: {
                                    Task { await subscriptionManager.loadProducts() }
                                }) {
                                    Text(String(localized: "重試"))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(ThemeManager.accentColor)
                                }
                            }
                            .padding()
                        }
                    }
                    .padding(.horizontal, 20)

                    // Restore purchases
                    Button(action: {
                        Task { await subscriptionManager.restorePurchases() }
                    }) {
                        Text(String(localized: "恢復購買"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Legal links
                    VStack(spacing: 6) {
                        Text(String(localized: "訂閱將自動續費，可隨時在設定中取消"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 4) {
                            Link(String(localized: "隱私權政策"), destination: URL(string: "https://do-card.online/privacy")!)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Link(String(localized: "服務條款"), destination: URL(string: "https://do-card.online/terms")!)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 24)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color(.systemGray5))
                            )
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
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(subscriptionManager.errorMessage ?? "")
        }
        .onChange(of: subscriptionManager.tier) { _, newTier in
            if newTier == .premium {
                dismiss()
            }
        }
    }

    // MARK: - Feature Row

    private func featureRow(title: String, free: String, premium: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(free)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 60)

            Text(premium)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(ThemeManager.accentColor)
                .frame(width: 60)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Purchase Button

private struct PurchaseButton: View {
    let product: Product
    let label: String
    let sublabel: String
    let isBestValue: Bool

    @EnvironmentObject var subscriptionManager: SubscriptionManager

    var body: some View {
        Button(action: {
            Task { await subscriptionManager.purchase(product) }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(label)
                            .font(.headline)

                        if isBestValue {
                            Text(String(localized: "最划算"))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .cornerRadius(4)
                        }
                    }
                    Text(sublabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if subscriptionManager.purchaseInProgress {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isBestValue ? Color.orange.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isBestValue ? Color.orange.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.purchaseInProgress)
    }
}

#Preview {
    PaywallView()
        .environmentObject(SubscriptionManager.shared)
}
