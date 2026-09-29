import OSLog

enum AppLogger {
  private static let subsystem = AppConfiguration.bundleIdentifier

  static let app = Logger(subsystem: subsystem, category: "App")
  static let ps5 = Logger(subsystem: subsystem, category: "PS5")
  static let display = Logger(subsystem: subsystem, category: "Display")
  static let hdr = Logger(subsystem: subsystem, category: "HDR")
  static let galaxy = Logger(subsystem: subsystem, category: "Galaxy")
  static let clipboard = Logger(subsystem: subsystem, category: "Clipboard")
  static let audio = Logger(subsystem: subsystem, category: "Audio")
  static let automation = Logger(subsystem: subsystem, category: "Automation")
}
