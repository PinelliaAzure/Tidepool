# Tidepool 🐋

> Your AI budget, at a glance. · 让每一分余额，都有潮汐。

macOS 菜单栏里的大模型余额与余量仪表盘：鲸鱼旁边是你的余额，点开是一整片玻璃面板。

| 余额 | 套餐余量 |
|---|---|
| ![余额面板](docs/preview.png) | ![额度面板](docs/preview-quota.png) |

- **余额优先**：DeepSeek / Kimi 的 API 余额，GLM Coding Plan / Kimi Code 的 5 小时与周额度
- **额度节奏**：用「时间进度 vs 用量进度」判断会不会提前用完，而不是只给一个百分比
- **潮汐图**：余额采样的 7 天 / 30 天水位曲线
- **Runway**：日均消耗与「还能用几天」的预测
- **本地优先**：API Key 只进 macOS 钥匙串，数据只落本机，无遥测
- **原生质感**：SwiftUI + AppKit，跟随系统 Liquid Glass / 明暗 / 降低透明度
- **低额度提醒**：余额 < ¥10 或额度 < 10% 时发系统通知，每个周期只提醒一次

## 构建与运行

需要 macOS 14+ 与 Swift 5.9+（Xcode 或 Command Line Tools 均可）。

```bash
make app          # 打包 build/Tidepool.app
open build/Tidepool.app

make test         # 单元测试（Swift Testing）
make build        # 只编译

# 无 API Key 时预览面板（内存假数据，不读写真实账户）
swift run Tidepool --preview          # 余额视图
swift run Tidepool --preview-quota    # 额度视图
```

> 纯 Command Line Tools 环境下，macOS 27 SDK 缺少 SwiftUI 的宏插件（`SwiftUIMacros`），
> `Makefile` / `build-app.sh` 会自动回退到 MacOSX26.5 SDK；安装了完整 Xcode 则无需处理。

首次使用：右键菜单栏的鲸鱼 →「Tidepool 设置…」→ 添加 Provider → 粘贴 API Key →「保存并测试」。

## 数据来源

| Provider | 内容 | 接口 | 状态 |
|---|---|---|---|
| DeepSeek | 账户余额（总额 / 赠送 / 充值） | `GET https://api.deepseek.com/user/balance` | ✅ 官方文档 |
| Kimi / Moonshot | API 余额（可用 / 代金券 / 现金） | `GET https://api.moonshot.cn/v1/users/me/balance` | ✅ 官方文档 |
| Kimi Code | 5h / 周套餐余量 | `GET https://api.kimi.com/coding/v1/usages` | ⚠️ 非公开只读接口，可能变化 |
| GLM / Z.ai | Coding Plan 5h / 周 / MCP 月度额度 | `GET https://open.bigmodel.cn/api/monitor/usage/quota/limit`（国际 `api.z.ai`） | ⚠️ 非公开只读接口，可能变化 |

所有接口均为只读，不消耗额度。不做网页登录 / session 抓取。

## 路线图

- **M0（已完成）** 菜单栏外壳、玻璃面板、DeepSeek + Kimi 余额、Keychain、轮询调度、潮汐图、runway、设置窗口
- **M1（已完成）** GLM / Kimi Code 额度与双环卡片、额度节奏、低余额 / 低额度通知、菜单栏三种展示方式、Provider 排序
- **M2** Onboarding、本地 token 明细（OpenCode / Claude Code）、CSV 导出、额度历史
- **M3** 应用图标、Sparkle 更新、公证与 DMG、Homebrew Cask、中英双语

## 隐私

- 密钥存于 macOS 钥匙串（`dev.pinellia.tidepool`），不写入任何文件
- 采样与账户配置存于 `~/Library/Application Support/Tidepool/`
- 无任何分析 / 遥测 / 第三方上传

## License

MIT
