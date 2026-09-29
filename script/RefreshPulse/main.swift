import Foundation
import CoreGraphics
import Darwin

func emit(_ event: String, _ values: [String: Any] = [:]) {
  var out = values
  out["event"] = event
  out["time"] = ISO8601DateFormatter().string(from: Date())
  if var data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) {
    data.append(10)
    data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let n = write(STDOUT_FILENO, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        if n > 0 { offset += n } else if n < 0 && errno == EINTR { continue } else { break }
      }
    }
  }
}
func record(_ mode: CGDisplayMode) -> ModeRecord {
  ModeRecord(id: mode.ioDisplayModeID, width: mode.width, height: mode.height,
    pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight, hz: mode.refreshRate,
    flags: mode.ioFlags, usable: mode.isUsableForDesktopGUI())
}
final class Driver {
  typealias Info = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
  let library: UnsafeMutableRawPointer
  let info: Info
  init() throws {
    guard let lib = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) else {
      throw ProbeError("唯讀 UUID 查詢不可用")
    }
    guard let sym = dlsym(lib, "CoreDisplay_DisplayCreateInfoDictionary") else {
      dlclose(lib); throw ProbeError("UUID 查詢符號不存在")
    }
    library = lib; info = unsafeBitCast(sym, to: Info.self)
  }
  deinit { dlclose(library) }
  func capture() throws -> [ScreenRecord] {
    var ids = [UInt32](repeating: 0, count: 32); var count: UInt32 = 0
    guard CGGetOnlineDisplayList(32, &ids, &count) == .success, count > 0, count < 32 else {
      throw ProbeError("顯示配置不可用或不完整")
    }
    return try ids.prefix(Int(count)).sorted().map { id in
      guard let mode = CGDisplayCopyDisplayMode(id),
            let dict = info(id)?.takeRetainedValue() as? [String: Any],
            let uuid = dict["kCGDisplayUUID"] as? String else { throw ProbeError("身分／模式不可用") }
      let bounds = CGDisplayBounds(id)
      return ScreenRecord(id: id, uuid: uuid, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
        builtIn: CGDisplayIsBuiltin(id) != 0, active: CGDisplayIsActive(id) != 0,
        mirrored: CGDisplayIsInMirrorSet(id) != 0, main: CGDisplayIsMain(id) != 0,
        x: bounds.origin.x, y: bounds.origin.y, rotation: CGDisplayRotation(id), mode: record(mode))
    }
  }
  func modes(_ id: UInt32) -> [CGDisplayMode] {
    CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary) as? [CGDisplayMode] ?? []
  }
  func plan() throws -> PulsePlan {
    let before = try capture(); let target = try selectTarget(before)
    guard target.mode.hz == 240 else { throw ProbeError("本原型僅測目前 240 Hz；不自行選其他路線") }
    let candidates = modes(target.id).map(record).filter {
      $0.hz == 120 && $0.width == target.mode.width && $0.height == target.mode.height &&
      $0.pixelWidth == target.mode.pixelWidth && $0.pixelHeight == target.mode.pixelHeight &&
      $0.flags & ~UInt32(4) == target.mode.flags & ~UInt32(4) && $0.usable
    }
    guard candidates.count == 1 else { throw ProbeError("120 Hz 候選不唯一或不適用") }
    var temporary = before
    temporary[temporary.firstIndex(where: { $0.uuid == target.uuid })!].mode = candidates[0]
    let result = PulsePlan(original: before, temporary: temporary, uuid: target.uuid)
    try result.validate(); return result
  }
  func commit(from expected: [ScreenRecord], to destination: [ScreenRecord], uuid: String, phase: String) throws {
    let target = try selectTarget(destination, uuid: uuid)
    guard try capture() == expected,
          let mode = modes(target.id).first(where: { record($0) == target.mode }) else {
      throw ProbeError("提交前配置已改變或原模式不可用")
    }
    var tx: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&tx) == .success, let tx else { throw ProbeError("無法建立交易") }
    var submitted = false
    defer { if !submitted { CGCancelDisplayConfiguration(tx) } }
    guard CGConfigureDisplayWithDisplayMode(tx, target.id, mode, nil) == .success,
          try capture() == expected else { throw ProbeError("交易準備失敗或配置改變") }
    emit("commit_started", ["phase": phase, "mode": target.mode.fingerprint])
    let status = CGCompleteDisplayConfiguration(tx, .forSession); submitted = true
    emit("commit_returned", ["phase": phase, "cgError": status.rawValue])
    guard status == .success else { throw ProbeError("系統拒絕 \(phase)：\(status.rawValue)") }
  }
}

// Readiness travels on a dedicated pipe; no state files or shell invocation.
func readReady(_ fd: Int32) throws {
  var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
  guard poll(&p, 1, 3000) > 0 else { throw ProbeError("還原監護程序未就緒，零次切換") }
  var byte: UInt8 = 0
  guard read(fd, &byte, 1) == 1, byte == 82 else { throw ProbeError("監護就緒驗證失敗") }
}

func guardian(_ encoded: String, readOnly: Bool = false) throws {
  guard let data = Data(base64Encoded: encoded) else { throw ProbeError("監護資料無效") }
  let plan = try JSONDecoder().decode(PulsePlan.self, from: data); try plan.validate()
  let path = FileManager.default.temporaryDirectory.appendingPathComponent("PersonalControlCenter-refresh-return.lock").path
  let fd = open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
  guard fd >= 0 else { throw ProbeError("無法開啟測試鎖") }
  defer { close(fd) }
  guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw ProbeError("另一個更新率測試／還原仍在執行") }
  let driver = try Driver()
  guard try driver.capture() == plan.original else { throw ProbeError("監護基準已改變") }
  // stdout is readiness-only; subsequent diagnostic output goes to stderr.
  var ready: UInt8 = 82
  guard write(STDOUT_FILENO, &ready, 1) == 1 else { throw ProbeError("無法傳遞就緒訊號") }
  dup2(STDERR_FILENO, STDOUT_FILENO)
  emit("guardian_ready")
  var lastNotice = ProcessInfo.processInfo.systemUptime
  while true {
    var p = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN | POLLHUP), revents: 0)
    let result = poll(&p, 1, 250)
    if result < 0 { if errno == EINTR { continue }; throw ProbeError("監護管線失敗") }
    if result > 0 {
      var byte: UInt8 = 0
      let n = read(STDIN_FILENO, &byte, 1)
      if n == 0 { break } // EOF: parent finished or exited; sole restoration owner.
      if n < 0, errno != EINTR { throw ProbeError("監護讀取失敗") }
    }
    if ProcessInfo.processInfo.systemUptime - lastNotice > 15 {
      emit("guardian_waiting", ["warning": "父程序仍存活；不與可能未完成的同步交易競爭還原"])
      lastNotice = ProcessInfo.processInfo.systemUptime
    }
  }
  // Brief post-exit settling, followed by exact identity / configuration comparison.
  Thread.sleep(forTimeInterval: 0.1)
  if readOnly {
    guard try driver.capture() == plan.original else { throw ProbeError("唯讀監護檢查期間配置改變；零次切換") }
    emit("guardian_check_complete", ["commandsSent": 0]); return
  }
  let decision = try RecoveryOnce().run(driver.capture(), plan: plan) {
    try driver.commit(from: plan.temporary, to: plan.original, uuid: plan.uuid, phase: "restore240")
  }
  guard decision != .refuse else { throw ProbeError("非本次臨時配置；未覆寫，請在內建螢幕檢查") }
  Thread.sleep(forTimeInterval: 0.1)
  guard try driver.capture() == plan.original else { throw ProbeError("還原後配置不符；不重試，請手動檢查") }
  emit("guardian_complete", ["modeRestored": true, "restorationSent": decision == .restore,
    "hdrUnchanged": "unverified", "visualReturn": "unverified"])
}

func main() throws {
  signal(SIGPIPE, SIG_IGN)
  let args = Array(CommandLine.arguments.dropFirst())
  if args.count == 2, args[0] == "--verify-plan" {
    guard let data = Data(base64Encoded: args[1]) else { throw ProbeError("驗證資料無效") }
    let plan = try JSONDecoder().decode(PulsePlan.self, from: data)
    try plan.validate()
    let current = try Driver().capture()
    guard current == plan.original else {
      emit("verification_mismatch", ["snapshot": try JSONSerialization.jsonObject(with: JSONEncoder().encode(current))])
      throw ProbeError("新程序讀取的配置與原本不同")
    }
    emit("fresh_verification_complete", ["commandsSent": 0, "modeRestored": true]); return
  }
  if args == ["--help"] {
    print("Default: read-only candidate. --check-guardian: read-only child IPC/lock check. Apply: --apply-once --target-uuid UUID --expected-mode FINGERPRINT --hdr-baseline on|off --confirm-hdmi2. May black out twice. Guardian alone restores once on parent EOF. No HDR setter."); return
  }
  if args.count == 2, args[0] == "--guardian" { try guardian(args[1]); return }
  if args.count == 2, args[0] == "--guardian-check" { try guardian(args[1], readOnly: true); return }
  let checkGuardian = args == ["--check-guardian"]
  let automatic = args.count == 3 && args[0] == "--automatic-once" && args[1] == "--target-uuid" && UUID(uuidString: args[2]) != nil
  let parsing = (checkGuardian || automatic) ? [] : args
  var fields: [String: String] = [:]; var flags = Set<String>(); var i = 0
  while i < parsing.count {
    let key = parsing[i]
    guard fields[key] == nil, !flags.contains(key) else { throw ProbeError("重複參數") }
    if ["--apply-once", "--confirm-hdmi2"].contains(key) { flags.insert(key) }
    else if ["--target-uuid", "--expected-mode", "--hdr-baseline"].contains(key) {
      i += 1; guard i < parsing.count, !parsing[i].hasPrefix("--") else { throw ProbeError("缺少參數") }; fields[key] = parsing[i]
    } else { throw ProbeError("未知參數") }
    i += 1
  }
  let apply = automatic || !parsing.isEmpty
  if apply && !automatic {
    guard flags == Set(["--apply-once", "--confirm-hdmi2"]), fields.count == 3,
      let uuid = fields["--target-uuid"], UUID(uuidString: uuid) != nil,
      let fingerprint = fields["--expected-mode"], !fingerprint.isEmpty,
      ["on", "off"].contains(fields["--hdr-baseline"] ?? "") else { throw ProbeError("缺少現場基準或確認") }
  }
  let driver = try Driver(); let plan = try driver.plan()
  let target = try selectTarget(plan.original, uuid: plan.uuid)
  if !apply && !checkGuardian {
    emit("preflight_only", ["commandsSent": 0, "targetUUID": plan.uuid,
      "expectedMode": target.mode.fingerprint, "temporaryMode": try selectTarget(plan.temporary).mode.fingerprint,
      "hdrState": "unknown", "warning": "可能黑兩次；mode 資訊無法證明 HDR 保持"]); return
  }
  if apply {
    guard plan.uuid.caseInsensitiveCompare(automatic ? args[2] : fields["--target-uuid"]!) == .orderedSame,
      automatic || target.mode.fingerprint == fields["--expected-mode"] else { throw ProbeError("目標／模式不符") }
  }
  let child = Process(); let input = Pipe(); let ready = Pipe(); let trace = Pipe()
  child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
  child.arguments = [checkGuardian ? "--guardian-check" : "--guardian", try JSONEncoder().encode(plan).base64EncodedString()]
  child.standardInput = input; child.standardOutput = ready; child.standardError = trace
  try child.run()
  // Parent retains only its write end; no accidental parent-owned read end needed.
  input.fileHandleForReading.closeFile(); ready.fileHandleForWriting.closeFile(); trace.fileHandleForWriting.closeFile()
  defer { trace.fileHandleForReading.closeFile() }
  var inputClosed = false
  defer { if !inputClosed { input.fileHandleForWriting.closeFile() } }
  try readReady(ready.fileHandleForReading.fileDescriptor)
  ready.fileHandleForReading.closeFile()
  var failure: Error?
  if apply { do {
    emit("operation_baseline", ["hdr": automatic ? "unknown" : fields["--hdr-baseline"]!,
      "evidence": automatic ? "PS5 online-to-rest; physical source unverified" : "operator supplied"])
    guard child.isRunning else { throw ProbeError("監護程序已退出") }
    try driver.commit(from: plan.original, to: plan.temporary, uuid: plan.uuid, phase: "temporary120")
    Thread.sleep(forTimeInterval: 0.1)
    guard try driver.capture() == plan.temporary else { throw ProbeError("臨時模式／配置不符") }
  } catch { failure = error } }
  input.fileHandleForWriting.closeFile() // Guardian owns exactly one possible restore.
  inputClosed = true
  let deadline = ProcessInfo.processInfo.systemUptime + 6
  while child.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
    Thread.sleep(forTimeInterval: 0.1)
  }
  guard !child.isRunning else { throw ProbeError("還原仍執行中；保留監護程序，不重試，請在內建螢幕檢查") }
  child.waitUntilExit()
  let childEvents = trace.fileHandleForReading.readDataToEndOfFile()
  if !childEvents.isEmpty {
    FileHandle.standardOutput.write(childEvents)
  }
  emit("guardian_exit", ["status": child.terminationStatus, "reason": child.terminationReason.rawValue])
  guard child.terminationStatus == 0 else {
    throw ProbeError("還原未驗證；請在內建螢幕手動檢查，不重試")
  }
  // Use a new read-only process: the process that set 120 Hz may retain stale
  // display state after the separate guardian restores 240 Hz. Keep full equality.
  let verifier = Process(); let verification = Pipe()
  verifier.executableURL = child.executableURL
  verifier.arguments = ["--verify-plan", try JSONEncoder().encode(plan).base64EncodedString()]
  verifier.standardOutput = verification; verifier.standardError = verification
  try verifier.run(); verification.fileHandleForWriting.closeFile()
  let verifyDeadline = ProcessInfo.processInfo.systemUptime + 3
  while verifier.isRunning && ProcessInfo.processInfo.systemUptime < verifyDeadline { Thread.sleep(forTimeInterval: 0.05) }
  guard !verifier.isRunning else { verifier.terminate(); throw ProbeError("唯讀驗證逾時；不重試寫入") }
  verifier.waitUntilExit()
  FileHandle.standardOutput.write(verification.fileHandleForReading.readDataToEndOfFile())
  verification.fileHandleForReading.closeFile()
  guard verifier.terminationStatus == 0 else { throw ProbeError("新程序未確認原配置；不重試") }
  if let failure { throw failure }
  if checkGuardian { emit("guardian_check_complete", ["commandsSent": 0]); return }
  emit("observation_complete", ["modeRestored": true, "visualReturn": "unverified", "hdrUnchanged": "unverified"])
}
do { try main() }
catch { emit("stopped", ["reason": String(describing: error), "retry": false]); exit(1) }
