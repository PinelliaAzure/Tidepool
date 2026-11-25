import AppKit
import SwiftUI

/// 首次启动引导：选 Provider → 填 Key 并验证 → 选菜单栏样式。
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome
        case credentials
        case menuBar
    }

    @Environment(AppStore.self) private var store

    var onFinish: (() -> Void)?
    var onSkip: (() -> Void)?

    @State private var step: Step
    @State private var provider: ProviderID = .deepseek
    @State private var keyInput = ""
    @State private var regionURL: URL = ProviderID.deepseek.defaultBaseURL
    @State private var preview: ProviderSnapshot?
    @State private var testError: String?
    @State private var isTesting = false
    @State private var style: MenuBarStyle = .single

    init(
        initialStep: Step = .welcome,
        onFinish: (() -> Void)? = nil,
        onSkip: (() -> Void)? = nil
    ) {
        _step = State(initialValue: initialStep)
        self.onFinish = onFinish
        self.onSkip = onSkip
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 24)

            Group {
                switch step {
                case .welcome:
                    welcomeStep
                case .credentials:
                    credentialsStep
                case .menuBar:
                    menuBarStep
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
                .padding(28)
        }
        .frame(width: 540, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: provider) { _, newValue in
            regionURL = defaultRegion(for: newValue)
            preview = nil
            testError = nil
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: StatusIconRenderer.whaleIcon(size: 52, tint: provider.nsBrandColor))
            VStack(alignment: .leading, spacing: 3) {
                Text("Tidepool")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("把 AI 余额放进菜单栏")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            stepDots
        }
    }

    private var stepDots: some View {
        HStack(spacing: 5) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item == step ? provider.brandColor : Color.primary.opacity(0.15))
                    .frame(width: item == step ? 16 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: step)
    }

    // MARK: - Step 1

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("先添加一个 Provider")
                .font(.system(size: 15, weight: .semibold))
            Text("余额型显示账户里还剩多少钱，套餐型显示 5 小时 / 每周还能用多少。之后可以随时在设置里添加更多。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(ProviderID.allCases) { option in
                    providerCard(option)
                }
            }
            .padding(.top, 2)
        }
    }

    private func providerCard(_ option: ProviderID) -> some View {
        let selected = option == provider
        return Button {
            provider = option
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(option.brandColor)
                        .frame(width: 8, height: 8)
                    Text(option.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(option.brandColor)
                    }
                }
                Text(option.kindDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? option.brandColor.opacity(0.10) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? option.brandColor.opacity(0.45) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(provider.brandColor).frame(width: 8, height: 8)
                Text("\(provider.displayName) 的 API Key")
                    .font(.system(size: 15, weight: .semibold))
            }
            Text(keyHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if supportsRegion {
                Picker("站点", selection: $regionURL) {
                    ForEach(regions, id: \.url) { option in
                        Text(option.label).tag(option.url)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            SecureField("粘贴 API Key", text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .onSubmit { test() }

            HStack(spacing: 8) {
                Button(isTesting ? "测试中…" : "测试连接") {
                    test()
                }
                .disabled(keyInput.count < 8 || isTesting)
                .controlSize(.small)
                if isTesting {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
            }

            resultCard
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        if let snapshot = preview {
            VStack(alignment: .leading, spacing: 7) {
                Label("连接成功", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                if let balance = snapshot.balance {
                    Text("余额 \(TideFormatter.money(balance.total, currency: balance.currency, style: .hero))")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                ForEach(snapshot.sortedQuotas) { quota in
                    HStack {
                        Text("\(quota.kind.displayName)额度")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(TideFormatter.percent(quota.remainingPercent))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                }
                if let plan = snapshot.planName {
                    Text(plan)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.green.opacity(0.08))
            )
        } else if let testError {
            Label(testError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
        } else {
            Text("Key 只保存进 macOS 钥匙串，Tidepool 只做只读查询。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Step 3

    private var menuBarStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("菜单栏想怎么显示？")
                .font(.system(size: 15, weight: .semibold))
            Text("之后可以在 Settings → 菜单栏 随时切换。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text("预览")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Image(nsImage: StatusIconRenderer.menuBarIcon(tint: provider.nsBrandColor))
                    Text(menuBarSample)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .padding(.vertical, 2)

            ForEach(MenuBarStyle.allCases) { option in
                styleCard(option)
            }
        }
    }

    private func styleCard(_ option: MenuBarStyle) -> some View {
        let selected = option == style
        return Button {
            style = option
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? provider.brandColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(styleDescription(option))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? provider.brandColor.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? provider.brandColor.opacity(0.4) : Color.primary.opacity(0.07),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack(spacing: 10) {
            if step == .welcome {
                Button("跳过，稍后设置") {
                    Prefs.onboardingDone = true
                    onSkip?()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Button("上一步") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        step = Step(rawValue: step.rawValue - 1) ?? .welcome
                    }
                }
                .controlSize(.small)
            }

            Spacer()

            Button(step == .menuBar ? "开始使用" : "继续") {
                advance()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!canContinue)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var canContinue: Bool {
        switch step {
        case .welcome: return true
        case .credentials: return preview != nil
        case .menuBar: return true
        }
    }

    private func advance() {
        switch step {
        case .welcome:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { step = .credentials }
        case .credentials:
            guard preview != nil else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { step = .menuBar }
        case .menuBar:
            finish()
        }
    }

    private func finish() {
        let account = store.addAccount(provider: provider, name: provider.displayName)
        store.setAPIKey(id: account.id, key: keyInput)
        store.updateAccount(id: account.id) { $0.baseURL = regionURL }
        store.selectAccount(id: account.id)
        store.setMenuBarStyle(style)
        Prefs.onboardingDone = true
        Task { await store.refresh(account.id, force: true) }
        onFinish?()
    }

    // MARK: - 测试 / 文案

    private func test() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 8 else { return }
        isTesting = true
        testError = nil
        preview = nil
        let selectedProvider = provider
        let base = regionURL
        Task {
            do {
                let adapter = ProviderRegistry.make(for: selectedProvider)
                let snapshot = try await adapter.fetch(apiKey: key, baseURL: base)
                await MainActor.run {
                    preview = snapshot
                    isTesting = false
                }
            } catch {
                let message = (error as? ProviderError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    testError = message
                    isTesting = false
                }
            }
        }
    }

    private var keyHint: String {
        switch provider {
        case .deepseek: return "在 platform.deepseek.com 的 API Keys 页面创建，仅用于读取余额。"
        case .moonshot: return "在 platform.moonshot.cn（国际站 platform.kimi.ai）创建；站点与 Key 必须匹配。"
        case .glm: return "在 open.bigmodel.cn 或 z.ai 的 Coding Plan 页面获取 Key。"
        case .kimiCode: return "在 platform.kimi.com 的 Kimi For Coding 页面获取 Coding Key（sk-…）。"
        }
    }

    private var menuBarSample: String {
        let value: String
        if let balance = preview?.balance {
            value = TideFormatter.money(balance.total, currency: balance.currency, style: .menuBar)
        } else if let quota = preview?.sortedQuotas.first {
            value = TideFormatter.percent(quota.remainingPercent)
        } else {
            value = "¥42.50"
        }
        switch style {
        case .single:
            return value
        case .all:
            return "\(value) · 72%"
        case .tightest:
            return preview?.sortedQuotas.first?.remainingPercent != nil ? value : "¥1.3k"
        }
    }

    private func styleDescription(_ option: MenuBarStyle) -> String {
        switch option {
        case .single: return "只显示当前 Provider，最干净"
        case .all: return "所有 Provider 并排显示，信息最全"
        case .tightest: return "只显示剩余最少的那一项，最省空间"
        }
    }

    private var supportsRegion: Bool {
        provider == .moonshot || provider == .glm
    }

    private struct RegionOption {
        var label: String
        var url: URL
    }

    private var regions: [RegionOption] {
        switch provider {
        case .moonshot:
            return [
                RegionOption(label: "国内 · moonshot.cn", url: URL(string: "https://api.moonshot.cn")!),
                RegionOption(label: "国际 · moonshot.ai", url: URL(string: "https://api.moonshot.ai")!)
            ]
        case .glm:
            return [
                RegionOption(label: "智谱 · bigmodel.cn", url: URL(string: "https://open.bigmodel.cn")!),
                RegionOption(label: "国际 · z.ai", url: URL(string: "https://api.z.ai")!)
            ]
        default:
            return []
        }
    }

    private func defaultRegion(for provider: ProviderID) -> URL {
        switch provider {
        case .glm: return URL(string: "https://open.bigmodel.cn")!
        case .moonshot: return URL(string: "https://api.moonshot.cn")!
        default: return provider.defaultBaseURL
        }
    }
}
