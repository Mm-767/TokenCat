import Foundation

/// 어시스턴트 응답 1건의 토큰 사용량 (JSONL 1레코드에서 추출, 중복 제거 전).
public struct UsageEvent: Equatable, Sendable {
    public let timestamp: Date
    public let model: String
    public let requestId: String
    public let messageId: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int

    /// 중복 제거 키. docs/jsonl-schema.md: 같은 응답이 최대 6줄로 중복 기록됨.
    public var dedupKey: String { "\(messageId):\(requestId)" }

    /// 총 토큰 = 4개 필드 합 (ccusage와 동일 규칙).
    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    public init(timestamp: Date, model: String, requestId: String, messageId: String,
                inputTokens: Int, outputTokens: Int,
                cacheCreationTokens: Int, cacheReadTokens: Int) {
        self.timestamp = timestamp
        self.model = model
        self.requestId = requestId
        self.messageId = messageId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
    }
}
