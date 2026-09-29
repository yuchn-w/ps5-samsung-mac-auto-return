import Foundation

@MainActor
final class AppState: ObservableObject {
  @Published private(set) var modules: [any DeviceModule]
  @Published var navigationPath: [AppDestination] = []
  @Published private(set) var lifecycleStatus: ServiceStatus = .idle
  let automationCoordinator: AutomationCoordinator
  let displayModule: DisplayModule

  init() {
    let display = DisplayModule()
    displayModule = display
    modules = [
      PS5Module(), display, GalaxyModule(), SonyHeadphonesModule(),
      AdamSpeakersModule(), HDRModule(), ClipboardModule(), SceneHarborModule(),
    ]
    automationCoordinator = AutomationCoordinator(display: display)
    for module in modules {
      module.onStatusChange = { [weak self] in
        self?.objectWillChange.send()
      }
    }
  }

  func startModules() {
    lifecycleStatus = .starting
    automationCoordinator.start()
    for module in modules {
      module.start()
    }
    lifecycleStatus = .running
  }

  func stopModules() {
    automationCoordinator.stop()
    for module in modules {
      module.stop()
    }
    lifecycleStatus = .stopped
  }

  func module(withID id: String) -> (any DeviceModule)? {
    modules.first { $0.id == id }
  }
}
