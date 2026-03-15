import SwiftUI

struct DomainPicker: View {
  @EnvironmentObject var themeManager: ThemeManager

  @Binding var domains: [String]
  @Binding var isPresented: Bool

  @State private var searchText: String = ""
  @State private var showingError: Bool = false
  @State private var errorMessage: String = ""

  private let maxDomains = 50

  private let popularDomains: [String] = [
    "amazon.com",
    "facebook.com",
    "instagram.com",
    "reddit.com",
    "tiktok.com",
    "youtube.com",
    "x.com",
  ]

  // MARK: - Computed Properties

  private var filteredPopularDomains: [String] {
    if searchText.isEmpty { return popularDomains }
    let query = searchText.lowercased()
    return popularDomains.filter { $0.localizedCaseInsensitiveContains(query) }
  }

  private var customDomains: [String] {
    domains.filter { !popularDomains.contains($0) }
  }

  private var filteredCustomDomains: [String] {
    if searchText.isEmpty { return customDomains }
    let query = searchText.lowercased()
    return customDomains.filter { $0.localizedCaseInsensitiveContains(query) }
  }

  private var canAddCustomDomain: Bool {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return false }
    guard isValidDomain(trimmed) else { return false }
    guard !domains.contains(trimmed) else { return false }
    guard !popularDomains.contains(trimmed) else { return false }
    guard domains.count < maxDomains else { return false }
    return true
  }

  // MARK: - Body

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        searchBar

        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            if canAddCustomDomain {
              addCustomDomainRow
            }

            if !filteredPopularDomains.isEmpty {
              sectionHeader(String(localized: "熱門網站"))

              ForEach(filteredPopularDomains, id: \.self) { domain in
                domainRow(domain: domain)
              }
            }

            if !filteredCustomDomains.isEmpty {
              sectionHeader(String(localized: "已新增的網站"))

              ForEach(filteredCustomDomains, id: \.self) { domain in
                domainRow(domain: domain)
              }
            }
          }
          .padding(.bottom, 20)
        }

        doneButton
      }
      .background(Color(.systemBackground))
      .navigationTitle(String(localized: "封鎖網站"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { isPresented = false }) {
            Image(systemName: "chevron.left")
              .fontWeight(.medium)
          }
        }
      }
      .alert(String(localized: "Error"), isPresented: $showingError) {
        Button(String(localized: "OK")) {}
      } message: {
        Text(errorMessage)
      }
    }
  }

  // MARK: - Search Bar

  private var searchBar: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundColor(.gray)

      TextField(String(localized: "搜尋網站"), text: $searchText)
        .autocapitalization(.none)
        .keyboardType(.URL)
        .textContentType(.URL)
        .onSubmit {
          addCustomDomainFromSearch()
        }

      if !searchText.isEmpty {
        Button(action: { searchText = "" }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.gray)
        }
      }
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(.secondarySystemBackground))
    )
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 8)
  }

  // MARK: - Add Custom Domain Row

  private var addCustomDomainRow: some View {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    return Button(action: { addCustomDomainFromSearch() }) {
      HStack {
        Image(systemName: "plus.circle.fill")
          .foregroundColor(themeManager.themeColor)
          .font(.title3)

        Text(String(localized: "新增 \"\(trimmed)\""))
          .foregroundColor(.primary)

        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color(.secondarySystemBackground))
      )
      .padding(.horizontal, 16)
      .padding(.top, 8)
    }
    .buttonStyle(.plain)
  }

  // MARK: - Section Header

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.subheadline)
      .foregroundColor(.secondary)
      .padding(.horizontal, 20)
      .padding(.top, 20)
      .padding(.bottom, 8)
  }

  // MARK: - Domain Row

  private func domainRow(domain: String) -> some View {
    let isSelected = domains.contains(domain)

    return Button(action: { toggleDomain(domain) }) {
      HStack {
        Text(domain)
          .foregroundColor(.primary)
          .font(.body)

        Spacer()

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundColor(isSelected ? themeManager.themeColor : Color(.tertiaryLabel))
          .font(.title3)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color(.secondarySystemBackground))
      )
      .padding(.horizontal, 16)
      .padding(.vertical, 3)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  // MARK: - Done Button

  private var doneButton: some View {
    Button(action: { isPresented = false }) {
      Text(String(localized: "完成"))
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(domains.isEmpty ? .white : .black)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
          Capsule()
            .fill(domains.isEmpty ? Color(.systemGray2) : themeManager.themeColor)
        )
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 30)
    .padding(.top, 8)
    .animation(.easeInOut(duration: 0.25), value: domains.isEmpty)
  }

  // MARK: - Actions

  private func toggleDomain(_ domain: String) {
    if let index = domains.firstIndex(of: domain) {
      domains.remove(at: index)
    } else {
      guard domains.count < maxDomains else {
        showError(String(localized: "Maximum number of domains (50) reached"))
        return
      }
      domains.append(domain)
    }
  }

  private func addCustomDomainFromSearch() {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    guard !trimmed.isEmpty else { return }

    guard domains.count < maxDomains else {
      showError(String(localized: "Maximum number of domains (50) reached"))
      return
    }

    guard !domains.contains(trimmed) else {
      showError(String(localized: "Domain already exists"))
      return
    }

    guard isValidDomain(trimmed) else {
      showError(String(localized:
        "Enter a valid domain without https:// or www. (e.g., google.com, reddit.com, facebook.com)"
      ))
      return
    }

    domains.append(trimmed)
    searchText = ""
  }

  private func showError(_ message: String) {
    errorMessage = message
    showingError = true
  }

  private func isValidDomain(_ domain: String) -> Bool {
    // Basic domain validation
    let domainRegex =
      #"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"#
    let predicate = NSPredicate(format: "SELF MATCHES %@", domainRegex)

    // Additional checks
    guard domain.count <= 253 else { return false }  // Max domain length
    guard !domain.hasPrefix(".") && !domain.hasSuffix(".") else { return false }
    guard !domain.contains("..") else { return false }  // No consecutive dots
    guard domain.contains(".") else { return false }  // Must have at least one dot

    return predicate.evaluate(with: domain)
  }
}

#Preview {
  @Previewable @State var domains: [String] = ["example.com", "reddit.com", "youtube.com"]

  DomainPicker(
    domains: $domains,
    isPresented: .constant(true)
  )
  .environmentObject(ThemeManager.shared)
}
