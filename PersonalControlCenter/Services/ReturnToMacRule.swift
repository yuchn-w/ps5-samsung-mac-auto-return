import Foundation

/// A transport gap is not standby. Retain a recent definite Online observation
/// briefly, but only a definite Rest reply can consume it and trigger once.
struct ReturnToMacRule {
  static let onlineRetention: TimeInterval = 60
  private(set) var armed = false
  private var lastOnline: TimeInterval?
  mutating func reset() { armed = false; lastOnline = nil }
  @discardableResult
  mutating func transportFailed(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
    guard let lastOnline, now >= lastOnline, now - lastOnline <= Self.onlineRetention else {
      reset(); return false
    }
    return armed
  }
  mutating func observe(_ status: DeviceStatus, enabled: Bool,
                        now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
    guard enabled else { reset(); return false }
    switch status {
    case .online: armed = true; lastOnline = now; return false
    case .restMode:
      let result = transportFailed(now: now)
      reset()
      return result
    case .offline:
      transportFailed(now: now)
      return false
    default: reset(); return false
    }
  }
}
