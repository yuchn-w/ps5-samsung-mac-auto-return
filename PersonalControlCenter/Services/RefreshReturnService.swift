import Foundation

/// Runs the bundled, guarded helper away from the main actor. Once started,
/// its independent guardian must be allowed to restore even if automation stops.
final class RefreshReturnService: @unchecked Sendable {
  // Public builds never contain the original tester's device identifier.
  static var verifiedUUID: String {
    (UserDefaults.standard.string(forKey: "refreshReturnTargetUUID") ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
  private let queue = DispatchQueue(label: "org.sceneharbor.PersonalControlCenter.refresh-return")
  var helperURL: URL? {
    Bundle.main.url(forResource: "probe-refresh-pulse", withExtension: nil)
  }
  var available: Bool {
    UUID(uuidString: Self.verifiedUUID) != nil &&
      (helperURL.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false)
  }
  func run(completion: @escaping @Sendable (Bool, String, Double) -> Void) {
    queue.async { [self] in
      let started = ProcessInfo.processInfo.systemUptime
      guard let url = helperURL else { completion(false, "缺少螢幕切換工具", 0); return }
      let process = Process(); let output = Pipe()
      process.executableURL = url
      process.arguments = ["--automatic-once", "--target-uuid", Self.verifiedUUID]
      process.standardOutput = output; process.standardError = output
      // Writable per-user lock location, separate from the signed app bundle.
      process.currentDirectoryURL = FileManager.default.temporaryDirectory
      do {
        try process.run()
        output.fileHandleForWriting.closeFile()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        output.fileHandleForReading.closeFile()
        process.waitUntilExit()
        let log = String(decoding: data, as: UTF8.self)
        completion(process.terminationStatus == 0 && log.contains("\"event\":\"observation_complete\""),
          log, ProcessInfo.processInfo.systemUptime - started)
      } catch { completion(false, error.localizedDescription, ProcessInfo.processInfo.systemUptime - started) }
    }
  }
}
