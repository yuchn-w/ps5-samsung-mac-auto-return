import AppKit

final class DisplayModule: PlaceholderModule, ObservableObject {
  @Published private(set) var isBusy = false
  @Published private(set) var lastResult = "尚未讀取螢幕"
  @Published private(set) var resultDate: Date?
  @Published private(set) var currentInput = "—"
  @Published private(set) var candidate: DisplayReading?
  @Published private var calibration = DisplayCalibration()
  var confirmations: Int { calibration.confirmations }
  var canConfirm: Bool { calibration.deadline.map { Date() < $0 } ?? false }
  var onCalibrationChanged: (() -> Void)?
  private let service = DisplayService()
  private var operation: DisplayOperation?
  private var automaticOperation = false
  private var generation = 0
  private var observers: [NSObjectProtocol] = []
  private var lifecycleObserver: NSObjectProtocol?
  private var running = false
  private var asleep = false
  private var verifiedIdentity: DisplayIdentity?
  private var confirmationTimer: Task<Void, Never>?
  private var refreshQueue = DisplayRefreshQueue()
  var canAutomaticallySwitch: Bool {
    running && !asleep && confirmations >= 2 && candidate != nil && verifiedIdentity == candidate?.identity
  }
  override var isAvailable: Bool { verifiedIdentity != nil }

  init() {
    super.init(
      id: "display", displayName: "Samsung G80SH", icon: "display", logger: AppLogger.display)
    if let data = UserDefaults.standard.data(forKey: "displayReturnCandidate") {
      candidate = try? JSONDecoder().decode(DisplayReading.self, from: data)
    }
    // Visible confirmations are intentionally session-local; no stale boot state.
  }

  override func start() {
    guard !running else { return }
    running = true
    lifecycleObserver = EventBus.shared.observe { [weak self] event in
      MainActor.assumeIsolated {
        guard let self else { return }
        switch event {
        case .systemWillSleep: self.asleep = true; self.invalidateCalibration()
        case .systemDidWake: self.asleep = false; self.refresh()
        default: break
        }
      }
    }
    observers.append(NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.invalidateCalibration()
        self?.refresh()
      }
    })
    refresh()
  }

  override func stop() {
    running = false
    refreshQueue.reset()
    invalidateCalibration()
    observers.forEach(NotificationCenter.default.removeObserver)
    observers.removeAll()
    if let lifecycleObserver { EventBus.shared.removeObserver(lifecycleObserver) }
    lifecycleObserver = nil
  }

  func cancelPending() {
    generation += 1
    operation?.cancel()
    confirmationTimer?.cancel()
    confirmationTimer = nil
    if isBusy && !automaticOperation { failCalibrationAttempt() }
    else if calibration.deadline != nil { failCalibrationAttempt() }
  }

  func cancelAutomaticPending() {
    if automaticOperation { cancelPending() }
  }

  private func invalidateCalibration() {
    cancelPending()
    failCalibrationAttempt()
    verifiedIdentity = nil
    updateStatus(.unavailable)
    onCalibrationChanged?()
    report("螢幕或系統狀態改變，請重新驗證校準")
  }

  func refresh() {
    guard refreshQueue.request(busy: isBusy, running: running, asleep: asleep) else { return }
    read(capture: false)
  }
  func captureMacInput() { read(capture: true) }

  private func read(capture: Bool) {
    guard running, !asleep, !isBusy else { return }
    if capture {
      calibration.reset()
      onCalibrationChanged?()
    }
    begin { [self] token in
      let first = try await service.read(operation: token)
      if capture {
        let second = try await service.read(operation: token)
        guard first.identity == second.identity, first.input == second.input, first.input > 0 else {
          throw DisplayFailure.message("連續讀值不一致，未保存候選輸入")
        }
      }
      return first
    } success: { [self] reading in
      verifiedIdentity = reading.identity
      currentInput = reading.hexInput
      if capture {
        candidate = reading
        if let data = try? JSONEncoder().encode(reading) {
          UserDefaults.standard.set(data, forKey: "displayReturnCandidate")
        }
        report("已記錄候選 \(reading.hexInput)，尚未證明可返回 USB-C")
      } else {
        if candidate?.identity != reading.identity { failCalibrationAttempt() }
        report("已讀取輸入 \(reading.hexInput)；不代表已切換畫面")
      }
      updateStatus(.online(detail: "DDC \(reading.hexInput)"))
    }
  }

  func returnToMac(automatic: Bool = false) {
    guard running, !asleep, !isBusy, let candidate else { return }
    guard !automatic || canAutomaticallySwitch else { return }
    begin { [self] token in
      try await service.switchInput(to: candidate, operation: token)
    } success: { [self] result in
      verifiedIdentity = result.after.identity
      currentInput = result.after.hexInput
      // Rewriting the same source does not establish an HDMI2 -> USB-C transition.
      if !automatic {
        calibration.readback(changed: result.before.input != result.after.input, now: Date())
        if canConfirm {
          confirmationTimer = Task {
            do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
            guard !Task.isCancelled, calibration.expire(now: Date()) else { return }
            onCalibrationChanged?()
            report("畫面確認已逾時，請重新開始兩次連續驗證")
          }
        } else { onCalibrationChanged?() }
      }
      let suffix = automatic ? "畫面尚未由使用者驗證"
        : (canConfirm ? "請確認三星是否真的從 HDMI 2 回到 Mac" : "來源值未變，不能算一次切換驗證")
      report("指令已送出，讀回 \(currentInput) 相符；\(suffix)")
      updateStatus(.online(detail: "DDC \(currentInput)"))
    }
    automaticOperation = automatic
  }

  func confirmVisibleReturn() {
    confirmationTimer?.cancel()
    confirmationTimer = nil
    guard calibration.confirm(now: Date()) else {
      onCalibrationChanged?()
      report("畫面確認已逾時，請重新開始兩次連續驗證")
      return
    }
    report("使用者已確認返回 Mac 畫面（\(confirmations)/2）")
    onCalibrationChanged?()
  }

  private func begin<T: Sendable>(
    work: @escaping (DisplayOperation) async throws -> T,
    success: @escaping (T) -> Void
  ) {
    cancelPending()
    let epoch = generation
    let token = DisplayOperation()
    operation = token
    automaticOperation = false
    isBusy = true
    report("正在與螢幕通訊…")
    Task {
      // Driver APIs are synchronous and not forcibly interruptible. Bound UI
      // waiting and reject further operations until the outstanding call returns.
      let watchdog = Task {
        try await Task.sleep(nanoseconds: 8_000_000_000)
        guard !Task.isCancelled, generation == epoch, token.expire() else { return }
        cancelPending()
        failCalibrationAttempt()
        report("DDC 等待逾時；停止後續操作，等待驅動程式返回")
      }
      defer {
        watchdog.cancel()
        isBusy = false
        operation = nil
        automaticOperation = false
        if refreshQueue.finished(running: running, asleep: asleep) { refresh() }
      }
      do {
        let result = try await work(token)
        guard generation == epoch, running, !asleep, token.complete() else { return }
        success(result)
      } catch {
        guard generation == epoch else { return }
        _ = token.complete()
        verifiedIdentity = nil
        failCalibrationAttempt()
        updateStatus(.unavailable)
        report(error.localizedDescription)
      }
    }
  }

  private func report(_ message: String) {
    lastResult = message
    resultDate = Date()
    AppLogger.display.info("\(message, privacy: .public)")
  }

  private func failCalibrationAttempt() {
    calibration.reset()
    confirmationTimer?.cancel()
    confirmationTimer = nil
    onCalibrationChanged?()
  }
}
