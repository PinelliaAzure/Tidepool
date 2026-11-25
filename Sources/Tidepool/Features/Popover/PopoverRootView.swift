import SwiftUI

/// 面板根视图：Provider 胶囊 Tab + Hero 余额 + 潮汐图 + Runway + Footer。
struct PopoverRootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.visibleAccounts.isEmpty {
                EmptyStateView()
            } else {
                mainContent
            }
        }
        .frame(width: 360)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            if let account = store.selectedAccount {
                if account.provider.isQuotaProvider {
                    QuotaHeroView(account: account)
                } else {
                    BalanceHeroView(account: account)
                    TideChartView(account: account)
                    RunwayView(account: account)
                }
                PopoverFooterView(account: account)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            if store.visibleAccounts.count > 1 {
                ForEach(store.visibleAccounts) { account in
                    tabPill(account)
                }
            } else if let account = store.selectedAccount {
                HStack(spacing: 6) {
                    Circle()
                        .fill(account.provider.brandColor)
                        .frame(width: 8, height: 8)
                    Text(account.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Button {
                store.requestSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func tabPill(_ account: ProviderAccount) -> some View {
        let isSelected = store.selectedAccount?.id == account.id
        return Button {
            store.selectAccount(id: account.id)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(account.provider.brandColor)
                    .frame(width: 7, height: 7)
                Text(account.name)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    isSelected
                        ? account.provider.brandColor.opacity(0.16)
                        : Color.primary.opacity(0.05)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? account.provider.brandColor.opacity(0.4) : .clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }
}

struct EmptyStateView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: StatusIconRenderer.whaleIcon(size: 84, tint: .secondaryLabelColor))
                .padding(.top, 8)
            VStack(spacing: 4) {
                Text("潮池还是空的")
                    .font(.headline)
                Text("添加一个 Provider，把余额放进菜单栏")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("添加 Provider") {
                store.requestSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .padding(.horizontal, 14)
    }
}
