import Foundation
import Combine
import UsageCore

/// JSONL 감시 → 집계 → burn rate → 고양이 상태 + 공식 % 폴링 + 한도 알림을 묶는 엔진.
/// 역할 분담(§2 하이브리드): 게이지 % = 공식 엔드포인트, 속도·토큰량·스파크라인 = 로컬 JSONL.
final class UsageEngine: ObservableObject {

    @Published var snapshot: UsageStore.Snapshot?
    @Published var burnRate: Double = 0
    @Published var catState: CatState = .sleeping
    /// 한도 임박 오버라이드 (§F2: 80% 🥵, 95% ⚠️). 세션/주간 중 높은 쪽 기준.
    @Published var alertLevel: UsageAlertLevel = .normal

    /// 마지막 공식 usage 성공 응답. nil = 미조회/실패/연동 off → 추정 모드 폴백.
    @Published var official: OfficialUsage?
    /// 마지막 공식 조회 이후 JSONL로 감지된 소모분 (보간 게이지용, §F3 갱신 전략).
    @Published var tokensSinceOfficial: Int = 0

    let settings: AppSettings

    /// 공식 폴링 간격 180초 고정 (429 방지 안전 간격).
    static let officialPollInterval: TimeInterval = 180
    /// 팝오버 열 때 재조회 생략 기준: 직전 조회 30초 이내.
    static let officialRefreshThrottle: TimeInterval = 30

    private let watcher = JSONLWatcher()
    private let store = UsageStore()
    private let meter = BurnRateMeter()
    private let provider = OAuthUsageProvider()
    private let workQueue = DispatchQueue(label: "tokencat.engine", qos: .utility)
    private var jsonlTimer: DispatchSourceTimer?
    private var officialTimer: DispatchSourceTimer?
    private var lastOfficialAttempt: Date?
    // 이하 상태는 workQueue 전용
    private var alertTracker = LimitAlertTracker()
    private var lastBlockStart: Date?

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    func start() {
        let jsonlTimer = DispatchSource.makeTimerSource(queue: workQueue)
        jsonlTimer.schedule(deadline: .now(), repeating: settings.pollInterval)
        jsonlTimer.setEventHandler { [weak self] in self?.tick() }
        jsonlTimer.resume()
        self.jsonlTimer = jsonlTimer

        let officialTimer = DispatchSource.makeTimerSource(queue: workQueue)
        officialTimer.schedule(deadline: .now() + 1, repeating: Self.officialPollInterval)
        officialTimer.setEventHandler { [weak self] in self?.fetchOfficial(throttled: false) }
        officialTimer.resume()
        self.officialTimer = officialTimer
    }

    /// 팝오버 열림/새로고침: JSONL 즉시 재스캔 + 공식 재조회(30초 스로틀).
    func refreshNow() {
        workQueue.async { [weak self] in
            self?.tick()
            self?.fetchOfficial(throttled: true)
        }
    }

    // MARK: - JSONL 틱 (3초)

    /// 메인 스레드 소유 상태의 동기 스냅샷 (틱당 1회).
    private struct MainState {
        let officialEnabled: Bool
        let sessionLimit: Int
        let weeklyLimit: Int
        let weeklyStart: Date
        let weeklyResetEnabled: Bool
        let sensitivity: Thresholds.Sensitivity
        let limitAlertsEnabled: Bool
        let newSessionAlertEnabled: Bool
        let official: OfficialUsage?
    }

    private func mainState(now: Date) -> MainState {
        DispatchQueue.main.sync {
            MainState(officialEnabled: settings.officialEnabled,
                      sessionLimit: settings.estimatedSessionLimit,
                      weeklyLimit: settings.estimatedWeeklyLimit,
                      weeklyStart: settings.weeklyWindowStart(now: now),
                      weeklyResetEnabled: settings.weeklyResetEnabled,
                      sensitivity: settings.sensitivity,
                      limitAlertsEnabled: settings.limitAlertsEnabled,
                      newSessionAlertEnabled: settings.newSessionAlertEnabled,
                      official: official)
        }
    }

    private func tick() {
        let now = Date()
        let main = mainState(now: now)

        store.add(watcher.scan(now: now))
        let snap = store.snapshot(now: now, weeklySince: main.weeklyStart)
        let rate = meter.update(tokensInLastMinute: snap.tokensLast60s)
        let idle = snap.lastEventDate.map { now.timeIntervalSince($0) } ?? .infinity
        let state = Thresholds.preset(sensitivity: main.sensitivity)
            .state(burnRate: rate, idleSeconds: idle)

        let official = main.officialEnabled ? main.official : nil
        let sinceOfficial = official.map { store.tokens(since: $0.fetchedAt, now: now) } ?? 0

        // 사용률 (공식 + 실측 역산 보간, 폴백 시 추정) — 팝오버 게이지와 동일 규칙(GaugeMath)
        let sessionPct: Double
        if let base = official?.sessionPercent {
            sessionPct = GaugeMath.interpolated(base: base,
                                                windowTokens: snap.currentBlock?.totalTokens ?? 0,
                                                tokensSince: sinceOfficial)
        } else {
            sessionPct = Double(snap.currentBlock?.totalTokens ?? 0) / Double(main.sessionLimit) * 100
        }
        let weeklyPct: Double
        if let base = official?.weeklyPercent {
            weeklyPct = GaugeMath.interpolated(base: base,
                                               windowTokens: snap.weeklyTokens,
                                               tokensSince: sinceOfficial)
        } else {
            weeklyPct = Double(snap.weeklyTokens) / Double(main.weeklyLimit) * 100
        }
        // 알림·오버라이드는 확정된 소스에서만: 공식 값 수신됨 or 연동 off(추정 모드 선택).
        // 연동 on인데 official==nil(시작 직후 미조회/일시 실패)이면 폴백 %가 순간 튀어
        // 오탐 알림·빨간 고양이가 나올 수 있으므로 평가를 보류한다.
        let authoritative = official != nil || !main.officialEnabled
        let level = authoritative
            ? UsageAlertLevel.level(percent: max(sessionPct, weeklyPct))
            : .normal

        if main.limitAlertsEnabled && authoritative {
            fireLimitAlerts(main: main, official: official, snap: snap,
                            sessionPct: sessionPct, weeklyPct: weeklyPct, burnRate: rate)
        }
        checkNewBlock(snap: snap, enabled: main.newSessionAlertEnabled)

        DispatchQueue.main.async {
            self.snapshot = snap
            self.burnRate = rate
            self.catState = state
            self.alertLevel = level
            self.tokensSinceOfficial = sinceOfficial
            if !main.officialEnabled { self.official = nil }  // 연동 off → 즉시 추정 모드
        }
    }

    // MARK: - 한도 알림 (§F4: 80%/95% 각 1회)

    private func fireLimitAlerts(main: MainState, official: OfficialUsage?,
                                 snap: UsageStore.Snapshot,
                                 sessionPct: Double, weeklyPct: Double, burnRate: Double) {
        // 창 식별자: 공식 리셋 시각 우선. 폴백 세션 = 블록 시작(안정),
        // 폴백 주간 = 사용자 리셋 시각(안정) or 롤링 모드는 상수
        // (now-7d는 매 틱 바뀌어 추적기가 리셋 → 알림 재발사되므로 금지).
        let sessionWindow = official?.sessionResetsAt.map { "\($0.timeIntervalSince1970)" }
            ?? snap.currentBlock.map { "\($0.start.timeIntervalSince1970)" } ?? "none"
        let weeklyWindow = official?.weeklyResetsAt.map { "\($0.timeIntervalSince1970)" }
            ?? (main.weeklyResetEnabled ? "\(main.weeklyStart.timeIntervalSince1970)" : "rolling")

        for threshold in alertTracker.alertsToFire(kind: .session, percent: sessionPct, windowId: sessionWindow) {
            // 남은 토큰: 공식 % 역산 스케일 우선, 폴백은 플랜 추정 한도
            let remainingTokens = official?.sessionPercent.flatMap {
                GaugeMath.remainingTokens(base: $0,
                                          windowTokens: snap.currentBlock?.totalTokens ?? 0,
                                          tokensSince: tokensSinceOfficialValue(official: official, snap: snap))
            } ?? Int((100 - sessionPct) / 100 * Double(main.sessionLimit))
            notify(threshold: threshold, kind: "세션",
                   remaining: remainingText(remainingTokens: remainingTokens, burnRate: burnRate))
        }
        for threshold in alertTracker.alertsToFire(kind: .weekly, percent: weeklyPct, windowId: weeklyWindow) {
            notify(threshold: threshold, kind: "주간", remaining: nil)
        }
    }

    private func tokensSinceOfficialValue(official: OfficialUsage?, snap: UsageStore.Snapshot) -> Int {
        guard let fetchedAt = official?.fetchedAt else { return 0 }
        return store.tokens(since: fetchedAt)
    }

    /// "약 1시간 12분 분량 남음(현재 속도 기준)" — 속도가 없으면 nil.
    private func remainingText(remainingTokens: Int, burnRate: Double) -> String? {
        guard burnRate >= 1, remainingTokens > 0 else { return nil }
        let minutes = Int(Double(remainingTokens) / burnRate)
        let text = minutes >= 60 ? "약 \(minutes / 60)시간 \(minutes % 60)분" : "약 \(minutes)분"
        return "\(text) 분량 남음(현재 속도 기준)"
    }

    private func notify(threshold: LimitAlertTracker.Threshold, kind: String, remaining: String?) {
        let emoji = threshold == .ninetyFive ? "⚠️" : "🥵"
        let title = "\(emoji) \(kind) 한도 \(threshold.rawValue)%"
        let body = remaining ?? "Claude Code /usage에서 정확한 잔여량을 확인하세요."
        DispatchQueue.main.async { Notifier.shared.send(title: title, body: body) }
    }

    /// 5시간 블록 리셋 감지 → "새 세션 시작!" (옵션, 기본 off).
    private func checkNewBlock(snap: UsageStore.Snapshot, enabled: Bool) {
        let start = snap.currentBlock?.start
        defer { lastBlockStart = start ?? lastBlockStart }
        guard enabled, let start, let previous = lastBlockStart, start != previous else { return }
        DispatchQueue.main.async {
            Notifier.shared.send(title: "🐱 새 세션 시작!", body: "5시간 사용량 창이 리셋되었습니다.")
        }
    }

    // MARK: - 공식 % 폴링 (180초)

    private func fetchOfficial(throttled: Bool) {
        let enabled = DispatchQueue.main.sync { settings.officialEnabled }
        guard enabled else {
            DispatchQueue.main.async { self.official = nil }
            return
        }
        if throttled, let last = lastOfficialAttempt,
           Date().timeIntervalSince(last) < Self.officialRefreshThrottle { return }
        lastOfficialAttempt = Date()

        Task { [weak self] in
            guard let self else { return }
            do {
                let usage = try await self.provider.fetch()
                await MainActor.run {
                    self.official = usage
                    self.tokensSinceOfficial = 0
                }
            } catch {
                // 실패 시 추정 모드 폴백 (§8 — 앱은 죽지 않는다). 다음 폴링에서 재시도.
                await MainActor.run { self.official = nil }
            }
        }
    }
}
