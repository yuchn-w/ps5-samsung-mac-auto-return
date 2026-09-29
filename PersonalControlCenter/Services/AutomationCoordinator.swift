import Foundation

@MainActor
final class AutomationCoordinator: ObservableObject {
  @Published private(set) var status: ServiceStatus = .idle
  @Published private(set) var activeAutomationCount = 0
  private var eventObserver: NSObjectProtocol?
  @Published private(set) var isEnabled = false
  @Published private(set) var summary = "未啟用"
  @Published private(set) var isSwitching = false
  @Published private(set) var lastDuration: Double?
  @Published private(set) var lastHelperLog = ""
  @Published private(set) var detectionLog = ""
  private let refreshReturn = RefreshReturnService()
  var canEnable: Bool { refreshReturn.available && !asleep }
  private var rule = ReturnToMacRule()
  private let display: DisplayModule
  private var asleep = false
  private var lastObservedState: DeviceStatus?
  private func record(_ message: String) {
    let line = "\(Date().description): \(message)"
    detectionLog = (detectionLog.components(separatedBy: "\n") + [line]).suffix(40).joined(separator: "\n")
    AppLogger.automation.info("\(message, privacy: .public)")
  }

  init(display: DisplayModule) { self.display = display }

  func setEnabled(_ enabled: Bool) {
    rule.reset()
    display.cancelAutomaticPending()
    isEnabled = enabled && canEnable
    UserDefaults.standard.set(isEnabled, forKey: "refreshReturnEnabled")
    activeAutomationCount = isEnabled ? 1 : 0
    status = isEnabled ? .running : .idle
    summary = isEnabled ? "等待 PS5 開機；待命後以更新率返回 Mac" : "未啟用"
    AppLogger.automation.info("Return-to-Mac rule enabled=\(self.isEnabled)")
  }

  func start() {
    guard eventObserver == nil else { return }
    eventObserver = EventBus.shared.observe { [weak self] event in
      MainActor.assumeIsolated { self?.handle(event) }
    }
    if ProcessInfo.processInfo.arguments.contains("--enable-refresh-return") {
      setEnabled(true)
    } else { setEnabled(UserDefaults.standard.bool(forKey: "refreshReturnEnabled")) }
    AppLogger.automation.info("Refresh-rate return automation started")
  }

  func stop() {
    rule.reset()
    isEnabled = false
    activeAutomationCount = 0
    if let eventObserver { EventBus.shared.removeObserver(eventObserver) }
    eventObserver = nil
    status = .idle
  }

  private func handle(_ event: AppEvent) {
    switch event {
    case .systemWillSleep:
      asleep = true
      rule.reset()
      activeAutomationCount = 0
      summary = "Mac 睡眠中，暫停偵測"
    case .systemDidWake:
      asleep = false
      rule.reset()
      activeAutomationCount = isEnabled ? 1 : 0
      if isEnabled { summary = "已喚醒，等待新的 PS5 開機觀測" }
    case .ps5MonitoringReset:
      rule.reset()
      lastObservedState = nil
      display.cancelAutomaticPending()
      if isEnabled { summary = "等待新的 PS5 開機觀測" }
      record("Monitoring reset: online observation discarded")
    case .ps5ProbeFailed(let count):
      let wasArmed = rule.armed
      let retained = rule.transportFailed()
      if isEnabled {
        summary = retained ? "PS5 暫未回應；保留近期開機觀測，等待明確待命" : "PS5 未回應，等待新的開機觀測"
      }
      if count == 1 || count == 3 || (wasArmed && !retained) {
        record("Probe gap count=\(count), recent Online retained=\(retained); no switch on timeout")
      }
    case .ps5StateChanged(let state):
      if state != .restMode { display.cancelAutomaticPending() }
      let wasArmed = rule.armed
      let shouldSwitch = rule.observe(state, enabled: isEnabled && !asleep && refreshReturn.available)
      if state != lastObservedState || wasArmed != rule.armed {
        record("PS5 reply=\(state.label), enabled=\(isEnabled), armedBefore=\(wasArmed), trigger=\(shouldSwitch)")
      }
      lastObservedState = state
      guard shouldSwitch else {
        if isEnabled, rule.armed, state != .offline { summary = "PS5 已開機，等待待命訊號" }
        return
      }
      guard !display.isBusy, !isSwitching else {
        summary = "螢幕忙碌，已略過本次切換"
        record("Return skipped: displayBusy=\(display.isBusy), switching=\(isSwitching)")
        return
      }
      isSwitching = true
      summary = "已偵測待命，正在 240 → 120 → 240 Hz"
      let enabledAtStart = isEnabled
      AppLogger.automation.info("PS5 online-to-rest: starting refresh-rate return immediately")
      refreshReturn.run { [weak self] success, log, elapsed in
        Task { @MainActor in
          guard let self else { return }
          self.isSwitching = false
          self.lastDuration = elapsed
          self.lastHelperLog = log
          AppLogger.automation.info("Refresh return elapsed=\(elapsed) success=\(success); \(log, privacy: .public)")
          if !success {
            self.setEnabled(false)
            self.summary = "切換未完整驗證，已停用；請檢查螢幕設定"
          } else if self.isEnabled && enabledAtStart && !self.asleep {
            self.summary = "已送出返回要求並確認還原 240 Hz；畫面待確認"
          }
        }
      }
    default: break
    }
  }
}
