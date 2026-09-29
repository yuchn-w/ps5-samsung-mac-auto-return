import Foundation
import CoreGraphics
import IOKit
import Darwin

struct DisplayIdentity: Codable, Equatable, Sendable {
  let uuid: String
  let registryID: UInt64
}

struct DisplayReading: Codable, Sendable {
  let identity: DisplayIdentity
  let input: UInt16
  var hexInput: String { String(format: "0x%02X", input) }
}

struct DisplaySwitchResult: Sendable {
  let before: DisplayReading
  let after: DisplayReading
}

/// Narrow support for one G80SH, with no dependency on other installed apps.
final class DisplayService: @unchecked Sendable {
  private let queue = DispatchQueue(label: "org.sceneharbor.PersonalControlCenter.ddc", qos: .utility)

  func read(operation: DisplayOperation) async throws -> DisplayReading {
    try await perform {
      try operation.check()
      return try DDCEndpoint().read(operation)
    }
  }

  func switchInput(to target: DisplayReading, operation: DisplayOperation) async throws -> DisplaySwitchResult {
    try await perform {
      try operation.check()
      let endpoint = try DDCEndpoint()
      guard endpoint.identity == target.identity else {
        throw DisplayFailure.message("螢幕連線已改變，請重新校準")
      }
      let before = try endpoint.read(operation)
      try operation.write { try endpoint.send(DDCPacket.setInput(target.input)) }
      AppLogger.display.info("DDC input write accepted; target=\(target.hexInput, privacy: .public)")
      Thread.sleep(forTimeInterval: 0.7)
      try operation.check()
      let fresh = try DDCEndpoint()
      guard fresh.identity == target.identity else {
        throw DisplayFailure.message("指令已送出，但螢幕連線改變；畫面尚未驗證")
      }
      let after = try fresh.read(operation)
      guard after.input == target.input else {
        throw DisplayFailure.message("指令已送出，但輸入讀回不符（\(after.hexInput)）")
      }
      return DisplaySwitchResult(before: before, after: after)
    }
  }

  private func perform<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { continuation.resume(with: Result { try body() }) }
    }
  }
}

private final class DDCEndpoint {
  typealias Create = @convention(c) (CFAllocator?, UInt32) -> Unmanaged<CFTypeRef>?
  typealias Transfer = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
  typealias Info = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
  let identity: DisplayIdentity
  private let service: CFTypeRef
  private let readI2C: Transfer
  private let writeI2C: Transfer
  // Keep dynamically loaded private symbols alive; absence fails closed.
  private static let ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
  private static let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)

  init() throws {
    guard let kit = Self.ioKit, let core = Self.coreDisplay,
          let createSymbol = dlsym(kit, "IOAVServiceCreateWithService"),
          let readSymbol = dlsym(kit, "IOAVServiceReadI2C"),
          let writeSymbol = dlsym(kit, "IOAVServiceWriteI2C"),
          let infoSymbol = dlsym(core, "CoreDisplay_DisplayCreateInfoDictionary") else {
      throw DisplayFailure.message("此 macOS 不支援目前的 DDC 介面")
    }
    var displays = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(32, &displays, &count) == .success, count < 32 else {
      throw DisplayFailure.message("無法列出顯示器")
    }
    let external = displays.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }
    guard let display = external.first,
          DisplayTargetPolicy.acceptsGraphics(externalCount: external.count,
            vendor: CGDisplayVendorNumber(display), model: CGDisplayModelNumber(display)) else {
      throw DisplayFailure.message("需要唯一一台已辨識的 Samsung G80SH 外接螢幕")
    }
    let getInfo = unsafeBitCast(infoSymbol, to: Info.self)
    guard let info = getInfo(display)?.takeRetainedValue() as? [String: Any],
          let uuid = info["kCGDisplayUUID"] as? String, !uuid.isEmpty else {
      throw DisplayFailure.message("無法取得螢幕穩定身分")
    }
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == 0 else {
      throw DisplayFailure.message("無法取得外接 DDC 連線")
    }
    defer { IOObjectRelease(iterator) }
    var candidates: [io_service_t] = []
    while true {
      let entry = IOIteratorNext(iterator)
      if entry == 0 { break }
      let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
      if location == "External" { candidates.append(entry) } else { IOObjectRelease(entry) }
    }
    defer { candidates.forEach { IOObjectRelease($0) } }
    guard DisplayTargetPolicy.acceptsTransport(count: candidates.count), let entry = candidates.first else {
      throw DisplayFailure.message("DDC 目標不唯一；已停止操作")
    }
    var registryID: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(entry, &registryID) == 0 else {
      throw DisplayFailure.message("無法驗證 DDC 連線身分")
    }
    let create = unsafeBitCast(createSymbol, to: Create.self)
    guard let av = create(kCFAllocatorDefault, entry)?.takeRetainedValue() else {
      throw DisplayFailure.message("無法開啟 DDC 連線")
    }
    identity = DisplayIdentity(uuid: uuid, registryID: registryID)
    service = av
    readI2C = unsafeBitCast(readSymbol, to: Transfer.self)
    writeI2C = unsafeBitCast(writeSymbol, to: Transfer.self)
  }

  func send(_ bytes: [UInt8]) throws {
    var bytes = bytes
    let code = bytes.withUnsafeMutableBytes { writeI2C(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
    guard code == 0 else { throw DisplayFailure.message("DDC 傳送失敗（\(code)）") }
  }

  func read(_ operation: DisplayOperation) throws -> DisplayReading {
    try operation.check()
    try send(DDCPacket.getInput())
    Thread.sleep(forTimeInterval: 0.08)
    try operation.check()
    var reply = [UInt8](repeating: 0, count: 12)
    let code = reply.withUnsafeMutableBytes { readI2C(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
    guard code == 0 else { throw DisplayFailure.message("DDC 讀取失敗（\(code)）") }
    return DisplayReading(identity: identity, input: try DDCPacket.input(from: reply))
  }
}
