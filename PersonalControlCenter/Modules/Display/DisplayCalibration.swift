import Foundation

struct DisplayCalibration {
  private(set) var confirmations = 0
  private(set) var deadline: Date?
  mutating func reset() { confirmations = 0; deadline = nil }
  mutating func abandonPendingConfirmation() {
    if deadline != nil { reset() }
  }
  mutating func readback(changed: Bool, now: Date) {
    guard changed else { reset(); return }
    deadline = now.addingTimeInterval(120)
  }
  mutating func confirm(now: Date) -> Bool {
    guard let deadline, now < deadline else { reset(); return false }
    confirmations = min(confirmations + 1, 2)
    self.deadline = nil
    return true
  }
  mutating func expire(now: Date) -> Bool {
    guard let deadline, now >= deadline else { return false }
    reset()
    return true
  }
}

/// Coalesces only reads. A pending write is never replayed after a link event.
struct DisplayRefreshQueue {
  private(set) var pending = false
  mutating func request(busy: Bool, running: Bool, asleep: Bool) -> Bool {
    guard running, !asleep else { return false }
    if busy { pending = true; return false }
    pending = false
    return true
  }
  mutating func finished(running: Bool, asleep: Bool) -> Bool {
    guard pending, running, !asleep else { return false }
    pending = false
    return true
  }
  mutating func reset() { pending = false }
}
