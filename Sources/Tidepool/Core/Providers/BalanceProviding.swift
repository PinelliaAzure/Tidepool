import Foundation

// MARK: - 错误

enum ProviderError: LocalizedError {
    case invalidKey
    case rateLimited
    case http(Int)
    case network(String)
    case notSupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "API Key 无效或已过期"
        case .rateLimited: return "请求过于频繁，已自动退避"
        case .http(let code): return "服务返回错误（HTTP \(code)）"
        case .network(let message): return "网络错误：\(message)"
        case .notSupported(let message): return message
        }
    }
}

// MARK: - HTTP 客户端

struct APIClient {
    func getJSON(url: URL, apiKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderError.network("无效的服务响应")
            }
            switch http.statusCode {
            case 200..<300:
                return data
            case 401, 403:
                throw ProviderError.invalidKey
            case 429:
                throw ProviderError.rateLimited
            default:
                throw ProviderError.http(http.statusCode)
            }
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.network(error.localizedDescription)
        }
    }
}

// MARK: - Provider 协议与注册表

protocol BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot
}

enum ProviderRegistry {
    static func make(for provider: ProviderID) -> BalanceProviding {
        switch provider {
        case .deepseek: return DeepSeekProvider()
        case .moonshot: return MoonshotProvider()
        case .kimiCode, .glm: return UnsupportedProvider(provider: provider)
        }
    }
}

struct UnsupportedProvider: BalanceProviding {
    let provider: ProviderID

    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        throw ProviderError.notSupported("\(provider.displayName) 的额度接口将在 M1 接入")
    }
}
