import Foundation
import Security

/// 공식 usage 엔드포인트 응답 (게이지 1순위 소스, docs/usage-endpoint.md).
public struct OfficialUsage: Equatable, Sendable {
    public let sessionPercent: Double?
    public let sessionResetsAt: Date?
    public let weeklyPercent: Double?
    public let weeklyResetsAt: Date?
    public let fetchedAt: Date

    public init(sessionPercent: Double?, sessionResetsAt: Date?,
                weeklyPercent: Double?, weeklyResetsAt: Date?, fetchedAt: Date) {
        self.sessionPercent = sessionPercent
        self.sessionResetsAt = sessionResetsAt
        self.weeklyPercent = weeklyPercent
        self.weeklyResetsAt = weeklyResetsAt
        self.fetchedAt = fetchedAt
    }
}

/// 비문서화 OAuth usage 엔드포인트 폴링 (180초 간격 준수).
/// ⚠ 토큰은 읽기 전용, Anthropic 외 어디에도 전송·로깅 금지.
/// 실패 시 호출측(엔진)이 추정 모드로 폴백한다.
public final class OAuthUsageProvider {

    public enum ProviderError: Error {
        case tokenNotFound
        case http(Int)
        case badResponse
    }

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// User-Agent 필수 — 없으면 공격적 레이트리밋 버킷(429 지속). docs/usage-endpoint.md.
    static let userAgent = "claude-code/2.1.207"

    public init() {}

    public func fetch() async throws -> OfficialUsage {
        guard let token = Self.loadAccessToken() else { throw ProviderError.tokenNotFound }
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.badResponse }
        guard http.statusCode == 200 else { throw ProviderError.http(http.statusCode) }
        guard let usage = Self.parse(data: data, fetchedAt: Date()) else { throw ProviderError.badResponse }
        return usage
    }

    // MARK: - 응답 파싱 (스키마-관용적: 필드 누락 시 nil, 둘 다 없으면 실패)

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 실측 응답은 마이크로초 6자리("…00.300459+00:00") — ISO8601DateFormatter가 못 읽는 경우 대비.
    static let microsecondsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        return f
    }()

    private static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        return isoFormatter.date(from: s)
            ?? isoFormatterNoFraction.date(from: s)
            ?? microsecondsFormatter.date(from: s)
    }

    private static func percent(_ any: Any?) -> Double? {
        (any as? NSNumber)?.doubleValue
    }

    public static func parse(data: Data, fetchedAt: Date) -> OfficialUsage? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }

        var sessionPct = percent((root["five_hour"] as? [String: Any])?["utilization"])
        var sessionReset = date((root["five_hour"] as? [String: Any])?["resets_at"])
        var weeklyPct = percent((root["seven_day"] as? [String: Any])?["utilization"])
        var weeklyReset = date((root["seven_day"] as? [String: Any])?["resets_at"])

        // 폴백: five_hour/seven_day가 없으면 limits[] 배열에서 추출
        if sessionPct == nil || weeklyPct == nil, let limits = root["limits"] as? [[String: Any]] {
            for limit in limits {
                switch limit["kind"] as? String {
                case "session" where sessionPct == nil:
                    sessionPct = percent(limit["percent"])
                    sessionReset = sessionReset ?? date(limit["resets_at"])
                case "weekly_all" where weeklyPct == nil:
                    weeklyPct = percent(limit["percent"])
                    weeklyReset = weeklyReset ?? date(limit["resets_at"])
                default: break
                }
            }
        }

        guard sessionPct != nil || weeklyPct != nil else { return nil }
        return OfficialUsage(sessionPercent: sessionPct, sessionResetsAt: sessionReset,
                             weeklyPercent: weeklyPct, weeklyResetsAt: weeklyReset,
                             fetchedAt: fetchedAt)
    }

    // MARK: - 토큰 로드 (macOS 키체인 → credentials.json 순, docs/usage-endpoint.md)

    static func loadAccessToken() -> String? {
        let json = keychainCredentials() ?? fileCredentials()
        guard let json,
              let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return token
    }

    private static func keychainCredentials() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func fileCredentials() -> Data? {
        let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return try? Data(contentsOf: configDir.appendingPathComponent(".credentials.json"))
    }
}
