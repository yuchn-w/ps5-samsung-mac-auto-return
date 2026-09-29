import Foundation

struct PulsePlan: Codable {
  let original: [ScreenRecord]
  let temporary: [ScreenRecord]
  let uuid: String
  func validate() throws {
    let a = try selectTarget(original, uuid: uuid)
    let b = try selectTarget(temporary, uuid: uuid)
    guard a.mode.hz == 240, b.mode.hz == 120,
          a.mode.id != b.mode.id, a.mode.width == b.mode.width,
          a.mode.height == b.mode.height, a.mode.pixelWidth == b.mode.pixelWidth,
          a.mode.pixelHeight == b.mode.pixelHeight,
          a.mode.flags & ~UInt32(4) == b.mode.flags & ~UInt32(4) else {
      throw ProbeError("必須為同尺寸的 240／120 Hz 模式；flags 僅允許預設模式旗標不同")
    }
    var expected = original
    guard let i = expected.firstIndex(where: { $0.uuid == uuid }) else { throw ProbeError("目標不存在") }
    expected[i].mode = b.mode
    guard expected == temporary else { throw ProbeError("臨時配置不可改排列、其他螢幕或身分") }
  }
}

enum RecoveryDecision: Equatable { case unchanged, restore, refuse }
func recoveryDecision(_ current: [ScreenRecord], _ plan: PulsePlan) -> RecoveryDecision {
  if current == plan.original { return .unchanged }
  if current == plan.temporary { return .restore }
  return .refuse
}

// The guardian is the only owner of restoration. A failed call is never retried.
final class RecoveryOnce {
  private(set) var consumed = false
  func run(_ current: [ScreenRecord], plan: PulsePlan,
           restore: () throws -> Void) throws -> RecoveryDecision {
    guard !consumed else { throw ProbeError("還原嘗試已消耗") }
    consumed = true
    try plan.validate()
    let decision = recoveryDecision(current, plan)
    if decision == .restore { try restore() }
    return decision
  }
}
