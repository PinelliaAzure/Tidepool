import AppKit

/// 打开「终端」执行官方 CLI 的浏览器登录流程。
/// 火山/阿里的登录本身是浏览器 SSO；Tidepool 不接触登录态。
@MainActor
enum CLILoginLauncher {
    static func open(for provider: ProviderID) {
        let script: String

        switch provider {
        case .volcengine:
            script = """
            #!/bin/bash
            export PATH="\(CLIExecutor.searchDirectories.joined(separator: ":")):$PATH"
            echo "Tidepool · 火山方舟 Coding Plan 登录"
            echo
            if ! command -v arkcli >/dev/null 2>&1; then
              echo "未安装 arkcli。请先在终端运行："
              echo "  npm install -g @volcengine/ark-cli"
              echo
              read -n 1 -s -r -p "按任意键关闭窗口…"
              exit 1
            fi
            arkcli auth login volc-sso
            echo
            echo "登录流程结束后，回到 Tidepool 点击「检测」。"
            read -n 1 -s -r -p "按任意键关闭窗口…"
            """
        case .alibaba:
            script = """
            #!/bin/bash
            export PATH="\(CLIExecutor.searchDirectories.joined(separator: ":")):$PATH"
            echo "Tidepool · 阿里云百炼 Coding Plan 登录"
            echo
            if ! command -v bl >/dev/null 2>&1; then
              echo "未安装百炼 CLI。请先在终端运行："
              echo "  curl -fsSL https://bailian.aliyun.com/cli/install.sh | BAILIAN_SKIP_SKILL_INIT=1 bash"
              echo
              read -n 1 -s -r -p "按任意键关闭窗口…"
              exit 1
            fi
            bl auth login --console
            echo
            echo "登录流程结束后，回到 Tidepool 点击「检测」。"
            read -n 1 -s -r -p "按任意键关闭窗口…"
            """
        default:
            return
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = directory.appendingPathComponent("tidepool-login-\(UUID().uuidString).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            let alert = NSAlert()
            alert.messageText = T("无法打开登录终端", "Cannot open the login terminal")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
