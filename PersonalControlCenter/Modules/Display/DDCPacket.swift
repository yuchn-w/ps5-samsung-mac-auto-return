import Foundation

enum DisplayTargetPolicy {
  static func acceptsGraphics(externalCount: Int, vendor: UInt32, model: UInt32) -> Bool {
    externalCount == 1 && vendor == 19501 && model == 31508
  }
  static func acceptsTransport(count: Int) -> Bool { count == 1 }
}

enum DDCPacket {
  static func getInput() -> [UInt8] { packet([0x82, 0x01, 0x60]) }
  static func setInput(_ value: UInt16) -> [UInt8] {
    packet([0x84, 0x03, 0x60, UInt8(value >> 8), UInt8(value & 0xff)])
  }
  private static func packet(_ bytes: [UInt8]) -> [UInt8] {
    bytes + [bytes.reduce(UInt8(0x6e ^ 0x51), ^)]
  }
  static func input(from bytes: [UInt8]) throws -> UInt16 {
    // Ignore the arbitrary IOAV padding byte after the 11-byte protocol reply.
    guard bytes.count >= 11, bytes[0] == 0x6e, bytes[1] == 0x88,
          bytes[2] == 0x02, bytes[3] == 0, bytes[4] == 0x60,
          bytes.prefix(11).reduce(UInt8(0x50), ^) == 0 else {
      throw DisplayFailure.message("螢幕回覆無效，無法確認輸入來源")
    }
    return UInt16(bytes[8]) << 8 | UInt16(bytes[9])
  }
}

enum DisplayFailure: LocalizedError {
  case message(String)
  var errorDescription: String? {
    switch self { case .message(let text): return text }
  }
}

final class DisplayOperation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  private var completed = false
  func cancel() { lock.lock(); cancelled = true; lock.unlock() }
  func complete() -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard !cancelled, !completed else { return false }
    completed = true
    return true
  }
  func expire() -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard !cancelled, !completed else { return false }
    cancelled = true
    completed = true
    return true
  }
  func check() throws {
    lock.lock(); defer { lock.unlock() }
    if cancelled { throw CancellationError() }
  }
  // Cancellation cannot undo an IO call that has already started.
  func write<T>(_ body: () throws -> T) throws -> T {
    lock.lock()
    guard !cancelled else { lock.unlock(); throw CancellationError() }
    // This is the commit point. Never hold the lock across a driver call,
    // otherwise cancellation on the main actor could wait for hardware.
    lock.unlock()
    return try body()
  }
}
