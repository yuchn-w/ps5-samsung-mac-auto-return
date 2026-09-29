import Foundation
import CoreGraphics
import Darwin

func emit(_ event: String, _ values: [String: Any] = [:]) {
  var value = values
  value["event"] = event
  value["time"] = ISO8601DateFormatter().string(from: Date())
  if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
  }
}

func record(_ mode: CGDisplayMode) -> ModeRecord {
  ModeRecord(id: mode.ioDisplayModeID, width: mode.width, height: mode.height,
             pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
             hz: mode.refreshRate, flags: mode.ioFlags, usable: mode.isUsableForDesktopGUI())
}

// Callbacks only record evidence. They never perform display operations.
final class Journal {
  private let lock = NSLock()
  private var events: [[String: Any]] = []
  private var total = 0
  func append(_ id: UInt32, _ flags: UInt32) {
    lock.lock(); defer { lock.unlock() }
    total += 1
    if events.count < 64 { events.append(["displayID": id, "flags": flags, "uptime": ProcessInfo.processInfo.systemUptime]) }
  }
  var count: Int { lock.lock(); defer { lock.unlock() }; return total }
  var entries: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return events }
}
let callback: CGDisplayReconfigurationCallBack = { display, flags, context in
  guard let context else { return }
  Unmanaged<Journal>.fromOpaque(context).takeUnretainedValue().append(display, flags.rawValue)
}

final class MacDriver: ReapplyDriver {
  typealias CreateInfo = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
  let library: UnsafeMutableRawPointer
  let createInfo: CreateInfo
  let journal: Journal
  init(journal: Journal) throws {
    self.journal = journal
    guard let library = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) else {
      throw ProbeError("唯讀身分查詢不可用")
    }
    guard let symbol = dlsym(library, "CoreDisplay_DisplayCreateInfoDictionary") else {
      dlclose(library); throw ProbeError("唯讀身分查詢符號不存在")
    }
    self.library = library
    createInfo = unsafeBitCast(symbol, to: CreateInfo.self)
  }
  deinit { dlclose(library) }
  func capture() throws -> [ScreenRecord] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(32, &ids, &count) == .success, count > 0, count < 32 else {
      throw ProbeError("無法讀取完整顯示配置；不推論為拔線")
    }
    return try ids.prefix(Int(count)).sorted().map { id in
      guard let mode = CGDisplayCopyDisplayMode(id),
            let info = createInfo(id)?.takeRetainedValue() as? [String: Any],
            let uuid = info["kCGDisplayUUID"] as? String else { throw ProbeError("模式或穩定身分不可用") }
      let bounds = CGDisplayBounds(id)
      return ScreenRecord(id: id, uuid: uuid, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                          builtIn: CGDisplayIsBuiltin(id) != 0, active: CGDisplayIsActive(id) != 0,
                          mirrored: CGDisplayIsInMirrorSet(id) != 0, main: CGDisplayIsMain(id) != 0,
                          x: bounds.origin.x, y: bounds.origin.y, rotation: CGDisplayRotation(id), mode: record(mode))
    }
  }
  func commitSameMode(expected: [ScreenRecord], target: ScreenRecord) throws {
    let epoch = journal.count
    guard try capture() == expected,
          let mode = CGDisplayCopyDisplayMode(target.id), record(mode) == target.mode else {
      throw ProbeError("提交前目標或模式已改變")
    }
    var transaction: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&transaction) == .success, let transaction else {
      throw ProbeError("無法建立顯示配置交易")
    }
    var completed = false
    defer { if !completed { CGCancelDisplayConfiguration(transaction) } }
    guard CGConfigureDisplayWithDisplayMode(transaction, target.id, mode, nil) == .success else {
      throw ProbeError("無法準備原模式重套")
    }
    guard try capture() == expected, journal.count == epoch else {
      throw ProbeError("提交前發生顯示器事件，已取消尚未提交的交易")
    }
    emit("commit_started", ["displayID": target.id, "uuid": target.uuid, "mode": target.mode.fingerprint,
                            "warning": "單次同步呼叫；可能無作用或黑畫面，無法中途撤回。"])
    // Session scope avoids process-exit rollback to a different permanent mode.
    // No HDR, origin, mirroring, refresh-rate alternatives, or power setters.
    let status = CGCompleteDisplayConfiguration(transaction, .forSession)
    completed = true // API consumes the transaction even on failure.
    emit("commit_returned", ["cgError": status.rawValue])
    guard status == .success else { throw ProbeError("系統拒絕交易（\(status.rawValue)）；不重試") }
  }
}

struct Arguments {
  var apply = false
  var help = false
  var uuid: String?
  var mode: String?
  var hdr: String?
  var hdmi2 = false
  init(_ args: [String]) throws {
    var seen = Set<String>()
    var i = 0
    while i < args.count {
      let key = args[i]
      guard seen.insert(key).inserted else { throw ProbeError("重複參數：\(key)") }
      switch key {
      case "--apply-once": apply = true
      case "--help": help = true
      case "--confirm-hdmi2": hdmi2 = true
      case "--target-uuid", "--expected-mode", "--hdr-baseline":
        i += 1
        guard i < args.count, !args[i].hasPrefix("--") else { throw ProbeError("缺少參數值：\(key)") }
        if key == "--target-uuid" { uuid = args[i] }
        if key == "--expected-mode" { mode = args[i] }
        if key == "--hdr-baseline" { hdr = args[i] }
      default: throw ProbeError("未知參數：\(key)")
      }
      i += 1
    }
    guard !help || args == ["--help"] else { throw ProbeError("--help 不可搭配其他參數") }
    if apply {
      guard let uuid, UUID(uuidString: uuid) != nil, let mode, !mode.isEmpty,
            let hdr, ["on", "off"].contains(hdr), hdmi2 else {
        throw ProbeError("執行需要 UUID、目前模式、HDR 基準與 HDMI 2 現場確認")
      }
    } else if !help && !args.isEmpty { throw ProbeError("只讀檢查不接受執行確認參數") }
  }
}

func main() throws {
  let args = try Arguments(Array(CommandLine.arguments.dropFirst()))
  if args.help {
    print("""
    Default: read-only preflight. Does not begin or commit a display transaction.
    Apply once (only with user present):
      --apply-once --target-uuid UUID --expected-mode FINGERPRINT
      --hdr-baseline on|off --confirm-hdmi2
    HDR baseline and HDMI 2 are operator observations, not machine verification.
    Never retry automatically. Same-mode application may be a no-op.
    """)
    return
  }
  // Serializes this tool's apply invocations without touching the running App.
  var lockFD: Int32 = -1
  if args.apply {
    let path = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
      .appendingPathComponent("mode-reapply.lock").path
    lockFD = open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard lockFD >= 0 else { throw ProbeError("無法建立測試鎖") }
    guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { close(lockFD); throw ProbeError("另一個單次測試仍在執行") }
  }
  defer { if lockFD >= 0 { close(lockFD) } }
  let journal = Journal()
  let context = Unmanaged.passUnretained(journal).toOpaque()
  guard CGDisplayRegisterReconfigurationCallback(callback, context) == .success else {
    throw ProbeError("無法登記唯讀顯示事件觀測")
  }
  defer { CGDisplayRemoveReconfigurationCallback(callback, context) }
  let driver = try MacDriver(journal: journal)
  if !args.apply {
    let screens = try driver.capture()
    let target = try selectTarget(screens)
    emit("preflight_only", ["targetUUID": target.uuid, "expectedMode": target.mode.fingerprint,
                            "hdrState": "unknown", "visualSource": "unknown", "displayCount": screens.count,
                            "commandsSent": 0])
    return
  }
  emit("operator_baseline", ["hdr": args.hdr!, "source": "HDMI 2", "sourceOfEvidence": "operator-supplied"])
  let engine = OneShotReapply()
  let after = try engine.run(driver: driver, request: ReapplyRequest(uuid: args.uuid!, expectedMode: args.mode!,
                                                          hdrBaseline: args.hdr!, hdmi2Confirmed: args.hdmi2))
  // Observe once for delayed configuration events; never schedule another write.
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
  let final = try driver.capture()
  _ = try selectTarget(final, uuid: args.uuid!)
  guard final == after else { throw ProbeError("觀察期間顯示配置改變；停止，不盲目還原") }
  emit("observation_complete", ["modeUnchanged": true, "visualReturn": "unverified",
                                "hdrUnchanged": "unverified", "events": journal.entries,
                                "warning": "API 成功不等於重新建立訊號或三星已顯示 Mac。"])
}

do { try main() }
catch { emit("stopped", ["reason": String(describing: error), "retry": false]); exit(1) }
