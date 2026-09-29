import Foundation

final class PS5Module: PlaceholderModule {
  private let service = PS5Service()
  private var timer: Timer?
  private var state = PS5State()
  private var generation = 0
  private var activeHost = ""
  private var running = false
  private var asleep = false
  private var probing = false
  private var lifecycleObserver: NSObjectProtocol?
  private var preferenceObserver: NSObjectProtocol?
  override var isAvailable: Bool { !activeHost.isEmpty }

  init() {
    super.init(id: "ps5", displayName: "PS5", icon: "gamecontroller", logger: AppLogger.ps5)
  }

  override func start() {
    guard !running else { return }
    running = true
    lifecycleObserver = EventBus.shared.observe { [weak self] event in
      MainActor.assumeIsolated {
        guard let self else { return }
        switch event {
        case .systemWillSleep: self.asleep = true; self.reset()
        case .systemDidWake: self.asleep = false; self.reset(); self.probe()
        default: break
        }
      }
    }
    preferenceObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.host != self.activeHost else { return }
        self.reset()
        self.probe()
      }
    }
    probe()
  }

  override func stop() {
    running = false
    reset()
    timer?.invalidate()
    timer = nil
    if let lifecycleObserver { EventBus.shared.removeObserver(lifecycleObserver) }
    if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
    lifecycleObserver = nil
    preferenceObserver = nil
  }

  private var host: String {
    UserDefaults.standard.string(forKey: "ps5Host")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private func reset() {
    timer?.invalidate()
    timer = nil
    generation += 1
    probing = false
    state = PS5State(status: .unavailable)
    updateStatus(.unavailable)
    EventBus.shared.post(.ps5MonitoringReset)
  }

  private func probe() {
    guard running, !asleep else { return }
    let host = self.host
    if host != activeHost { reset(); activeHost = host }
    guard !host.isEmpty else {
      state = PS5State(status: .notConfigured)
      updateStatus(.notConfigured)
      return
    }

    guard !probing else { return }
    probing = true
    generation += 1
    let epoch = generation
    service.probe(host: host) { [weak self] result in
      Task { @MainActor in
        guard let self, self.running, !self.asleep,
              self.generation == epoch, self.host == host else { return }
        self.probing = false
        let previous = self.state.status
        switch result {
        case .success(let status):
          self.state.consecutiveFailures = 0
          self.state.status = status
          self.updateStatus(status)
          if previous != status {
            AppLogger.ps5.info("PS5 state: \(status.label, privacy: .public)")
          }
          EventBus.shared.post(.ps5StateChanged(status))
        case .failure(let error):
          self.state.consecutiveFailures += 1
          EventBus.shared.post(.ps5ProbeFailed(count: self.state.consecutiveFailures))
          if self.state.consecutiveFailures == 1 || self.state.consecutiveFailures == 3 {
            AppLogger.ps5.info("Probe failed count=\(self.state.consecutiveFailures): \(error.localizedDescription, privacy: .public)")
          }
          guard self.state.consecutiveFailures >= 3 else { self.scheduleProbe(); return }
          self.state.status = .offline
          self.updateStatus(.offline)
          if previous != .offline {
            AppLogger.ps5.info("PS5 state: 未回應（電源狀態未知）")
            EventBus.shared.post(.ps5StateChanged(.offline))
          }
        }
        self.scheduleProbe()
      }
    }
  }

  private func scheduleProbe() {
    guard running, !asleep else { return }
    timer?.invalidate()
    let interval = PS5PollingPolicy.interval(for: state.status)
    let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.probe() }
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }
}
