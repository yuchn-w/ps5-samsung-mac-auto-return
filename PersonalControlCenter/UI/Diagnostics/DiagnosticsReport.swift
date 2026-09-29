import Foundation

enum DiagnosticsReport {
  @MainActor
  static func make(for appState: AppState) -> String {
    let bundle = Bundle.main
    let version =
      bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    let architecture = currentArchitecture
    let moduleLines = appState.modules.map { "\($0.displayName): \($0.status.label)" }.joined(
      separator: "\n")

    return """
      \(AppConfiguration.displayName) Diagnostics

      App
      Version: \(version)
      Build: \(build)
      macOS: \(os)
      Architecture: \(architecture)

      Modules
      \(moduleLines)

      Automation: \(appState.automationCoordinator.status.rawValue)
      Rule: \(appState.automationCoordinator.summary)
      Detection events: \(appState.automationCoordinator.detectionLog)
      Refresh return duration: \(appState.automationCoordinator.lastDuration?.description ?? "None")
      Refresh return log: \(appState.automationCoordinator.lastHelperLog)
      Display: \(appState.displayModule.lastResult)
      Display observation: \(appState.displayModule.resultDate?.description ?? "None")
      Visible confirmations: \(appState.displayModule.confirmations)/2
      """
  }

  private static var currentArchitecture: String {
    #if arch(arm64)
      return "Apple Silicon (arm64)"
    #elseif arch(x86_64)
      return "Intel (x86_64)"
    #else
      return "Unknown"
    #endif
  }
}
