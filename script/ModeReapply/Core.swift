import Foundation

struct ProbeError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

struct ModeRecord: Codable, Equatable {
  var id: Int32
  var width: Int
  var height: Int
  var pixelWidth: Int
  var pixelHeight: Int
  var hz: Double
  var flags: UInt32
  var usable: Bool
  var fingerprint: String {
    "\(id):\(width)x\(height):\(pixelWidth)x\(pixelHeight):\(hz):\(flags)"
  }
}

struct ScreenRecord: Codable, Equatable {
  var id: UInt32
  var uuid: String
  var vendor: UInt32
  var model: UInt32
  var builtIn: Bool
  var active: Bool
  var mirrored: Bool
  var main: Bool
  var x: Double
  var y: Double
  var rotation: Double
  var mode: ModeRecord
}

struct ReapplyRequest {
  var uuid: String
  var expectedMode: String
  var hdrBaseline: String
  var hdmi2Confirmed: Bool
}

func selectTarget(_ screens: [ScreenRecord], uuid: String? = nil) throws -> ScreenRecord {
  guard !screens.isEmpty, screens.count < 32 else { throw ProbeError("顯示器清單不可用或不完整") }
  guard screens.contains(where: { $0.builtIn && $0.active }) else {
    throw ProbeError("必須保留可用的 Mac 內建螢幕")
  }
  guard !screens.contains(where: { $0.mirrored }) else { throw ProbeError("不在鏡像模式下測試") }
  let external = screens.filter { !$0.builtIn }
  guard external.count == 1 else { throw ProbeError("必須只有一台外接顯示器") }
  let target = external[0]
  guard target.active, target.vendor == 19501, target.model == 31508,
        UUID(uuidString: target.uuid) != nil, target.mode.usable,
        target.mode.width > 0, target.mode.height > 0,
        target.mode.pixelWidth > 0, target.mode.pixelHeight > 0,
        target.mode.hz.isFinite, target.mode.hz > 0 else { throw ProbeError("目標不是可用的已知三星 G80SH") }
  if let uuid, target.uuid.caseInsensitiveCompare(uuid) != .orderedSame {
    throw ProbeError("顯示器 UUID 不符，拒絕切換")
  }
  return target
}

protocol ReapplyDriver {
  func capture() throws -> [ScreenRecord]
  // Implementations must revalidate immediately before the sole commit.
  func commitSameMode(expected: [ScreenRecord], target: ScreenRecord) throws
}

final class OneShotReapply {
  private(set) var consumed = false
  func run(driver: ReapplyDriver, request: ReapplyRequest) throws -> [ScreenRecord] {
    guard !consumed else { throw ProbeError("此次測試已消耗；不允許重試") }
    // Even a rejected or failed attempt is consumed; never queue retries.
    consumed = true
    guard UUID(uuidString: request.uuid) != nil, !request.expectedMode.isEmpty,
          ["on", "off"].contains(request.hdrBaseline), request.hdmi2Confirmed else {
      throw ProbeError("缺少目標、模式或使用者現場確認")
    }
    let before = try driver.capture()
    let target = try selectTarget(before, uuid: request.uuid)
    guard target.mode.fingerprint == request.expectedMode else { throw ProbeError("目前模式與基準不符") }
    guard try driver.capture() == before else { throw ProbeError("檢查期間顯示配置改變，拒絕切換") }
    try driver.commitSameMode(expected: before, target: target)
    let after = try driver.capture()
    guard after == before else {
      throw ProbeError("命令後配置不同；停止且不盲目還原，請在內建螢幕檢查設定")
    }
    return after
  }
}
