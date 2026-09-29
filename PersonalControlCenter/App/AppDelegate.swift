import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  let appState = AppState()
  private var menuBarController: MenuBarController?
  private var lifecycleObservers: [NSObjectProtocol] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    AppLogger.app.info("App launched")
    appState.startModules()
    menuBarController = MenuBarController(appState: appState)
    observeSystemLifecycle()
  }

  func applicationWillTerminate(_ notification: Notification) {
    appState.stopModules()
    lifecycleObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    AppLogger.app.info("App will terminate")
  }

  func showControlCenter() {
    menuBarController?.showPanel(on: NSApp.keyWindow?.screen)
  }

  private func observeSystemLifecycle() {
    let center = NSWorkspace.shared.notificationCenter
    lifecycleObservers.append(
      center.addObserver(
        forName: NSWorkspace.willSleepNotification,
        object: nil,
        queue: .main
      ) { _ in
        AppLogger.app.info("System will sleep")
        EventBus.shared.post(.systemWillSleep)
      })
    lifecycleObservers.append(
      center.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
      ) { _ in
        AppLogger.app.info("System did wake")
        EventBus.shared.post(.systemDidWake)
      })
  }
}
