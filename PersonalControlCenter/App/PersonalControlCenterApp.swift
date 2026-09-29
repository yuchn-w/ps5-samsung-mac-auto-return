import SwiftUI

@main
struct PersonalControlCenterApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      SettingsRootView()
    }
    .commands {
      CommandGroup(after: .appSettings) {
        Button("開啟個人控制中心") { appDelegate.showControlCenter() }
          .keyboardShortcut("k", modifiers: [.command, .shift])
      }
    }
  }
}

private struct SettingsRootView: View {
  @EnvironmentObject private var appDelegate: AppDelegate
  var body: some View {
    NativePopoverContainer(appState: appDelegate.appState)
  }
}
