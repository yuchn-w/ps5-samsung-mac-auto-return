import Foundation
#if !STANDALONE_TESTS
import XCTest
@testable import PersonalControlCenter
#else
// The CLT-only installation lacks XCTest. Run these same cases against the
// production sources through script/test_return_to_mac.sh without mocks of logic.
class XCTestCase {}
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
func XCTAssertEqual<T: Equatable>(_ value: @autoclosure () throws -> T, _ expected: T) {
  do { let actual = try value(); precondition(actual == expected) } catch { fatalError("Unexpected error: \(error)") }
}
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T) {
  do { _ = try value(); fatalError("Expected an error") } catch {}
}
#endif

final class ReturnToMacTests: XCTestCase {
  func testCompletionAndWatchdogHaveOnlyOneWinner() {
    let completed = DisplayOperation()
    XCTAssertTrue(completed.complete())
    XCTAssertFalse(completed.expire())
    XCTAssertFalse(completed.complete())
    let timedOut = DisplayOperation()
    XCTAssertTrue(timedOut.expire())
    XCTAssertFalse(timedOut.complete())
    XCTAssertThrowsError(try timedOut.check())
  }
  func testFailedCalibrationAttemptBreaksConsecutiveStreak() {
    let now = Date(timeIntervalSince1970: 1000)
    for failure in ["timeout", "expired", "same-source", "cancelled"] {
      var calibration = DisplayCalibration()
      calibration.readback(changed: true, now: now)
      XCTAssertTrue(calibration.confirm(now: now.addingTimeInterval(1)))
      XCTAssertEqual(calibration.confirmations, 1)
      switch failure {
      case "timeout": calibration.reset()
      case "expired":
        calibration.readback(changed: true, now: now)
        XCTAssertTrue(calibration.expire(now: now.addingTimeInterval(120)))
      case "same-source": calibration.readback(changed: false, now: now)
      default:
        calibration.readback(changed: true, now: now)
        calibration.abandonPendingConfirmation()
      }
      calibration.readback(changed: true, now: now)
      XCTAssertTrue(calibration.confirm(now: now.addingTimeInterval(1)))
      XCTAssertEqual(calibration.confirmations, 1)
    }
  }
  func testCalibrationDeadlineAndTwoDistinctConfirmations() {
    let now = Date(timeIntervalSince1970: 1000)
    var calibration = DisplayCalibration()
    calibration.readback(changed: true, now: now)
    XCTAssertFalse(calibration.confirm(now: now.addingTimeInterval(120)))
    XCTAssertEqual(calibration.confirmations, 0)
    for _ in 0..<2 {
      calibration.readback(changed: true, now: now)
      XCTAssertTrue(calibration.confirm(now: now.addingTimeInterval(1)))
    }
    XCTAssertEqual(calibration.confirmations, 2)
    XCTAssertFalse(calibration.expire(now: now.addingTimeInterval(500)))
  }
  func testBusyRefreshIsCoalescedAndResumesAfterWake() {
    var queue = DisplayRefreshQueue()
    for _ in 0..<3 { XCTAssertFalse(queue.request(busy: true, running: true, asleep: false)) }
    XCTAssertTrue(queue.finished(running: true, asleep: false))
    XCTAssertFalse(queue.finished(running: true, asleep: false))
    XCTAssertFalse(queue.request(busy: true, running: true, asleep: false))
    XCTAssertFalse(queue.finished(running: true, asleep: true))
    XCTAssertTrue(queue.request(busy: false, running: true, asleep: false))
    XCTAssertFalse(queue.pending)
    XCTAssertFalse(queue.request(busy: true, running: false, asleep: false))
    queue.reset()
    XCTAssertFalse(queue.finished(running: false, asleep: false))
  }
  func testOnlyUniqueKnownDisplayAndTransportAreAccepted() {
    XCTAssertTrue(DisplayTargetPolicy.acceptsGraphics(externalCount: 1, vendor: 19501, model: 31508))
    for count in [0, 2, 32] {
      XCTAssertFalse(DisplayTargetPolicy.acceptsGraphics(externalCount: count, vendor: 19501, model: 31508))
      XCTAssertFalse(DisplayTargetPolicy.acceptsTransport(count: count))
    }
    XCTAssertFalse(DisplayTargetPolicy.acceptsGraphics(externalCount: 1, vendor: 1552, model: 31508))
    XCTAssertFalse(DisplayTargetPolicy.acceptsGraphics(externalCount: 1, vendor: 19501, model: 0))
    XCTAssertTrue(DisplayTargetPolicy.acceptsTransport(count: 1))
  }
  func testOnlineRestIsOneShotAndCanRearm() {
    var rule = ReturnToMacRule()
    XCTAssertFalse(rule.observe(.restMode, enabled: true))
    XCTAssertFalse(rule.observe(.online(), enabled: true))
    XCTAssertTrue(rule.observe(.restMode, enabled: true))
    XCTAssertFalse(rule.observe(.restMode, enabled: true))
    XCTAssertFalse(rule.observe(.online(), enabled: true))
    XCTAssertTrue(rule.observe(.restMode, enabled: true))
  }
  func testUnknownOrDisabledBreaksSequence() {
    for status: DeviceStatus in [.notConfigured, .unavailable] {
      var rule = ReturnToMacRule()
      _ = rule.observe(.online(), enabled: true)
      XCTAssertFalse(rule.observe(status, enabled: true))
      XCTAssertFalse(rule.observe(.restMode, enabled: true))
    }
    var rule = ReturnToMacRule()
    _ = rule.observe(.online(), enabled: true)
    XCTAssertFalse(rule.observe(.restMode, enabled: false))
    XCTAssertFalse(rule.observe(.restMode, enabled: true))
  }
  func testLifecycleResetDisarms() {
    var rule = ReturnToMacRule()
    _ = rule.observe(.online(), enabled: true)
    rule.reset()
    XCTAssertFalse(rule.observe(.restMode, enabled: true))
  }
  func testTransportGapOnlyTriggersOnRecentDefiniteRest() {
    var rule = ReturnToMacRule()
    XCTAssertFalse(rule.transportFailed(now: 100))
    XCTAssertFalse(rule.observe(.restMode, enabled: true, now: 101))
    XCTAssertFalse(rule.observe(.online(), enabled: true, now: 200))
    XCTAssertTrue(rule.transportFailed(now: 202))
    XCTAssertFalse(rule.observe(.offline, enabled: true, now: 210))
    XCTAssertTrue(rule.observe(.restMode, enabled: true, now: 238))
    XCTAssertFalse(rule.observe(.restMode, enabled: true, now: 239))
  }
  func testRetentionExpiryAndClockReversalFailClosed() {
    var rule = ReturnToMacRule()
    _ = rule.observe(.online(), enabled: true, now: 100)
    XCTAssertFalse(rule.transportFailed(now: 161))
    XCTAssertFalse(rule.observe(.restMode, enabled: true, now: 162))
    _ = rule.observe(.online(), enabled: true, now: 200)
    XCTAssertFalse(rule.observe(.restMode, enabled: true, now: 261))
    _ = rule.observe(.online(), enabled: true, now: 300)
    XCTAssertFalse(rule.observe(.restMode, enabled: true, now: 299))
  }
  func testOnlineRepliesRefreshRetentionAndResetStillDisarms() {
    var rule = ReturnToMacRule()
    _ = rule.observe(.online(), enabled: true, now: 100)
    _ = rule.observe(.online(), enabled: true, now: 150)
    XCTAssertTrue(rule.observe(.restMode, enabled: true, now: 210))
    _ = rule.observe(.online(), enabled: true, now: 300)
    _ = rule.transportFailed(now: 302)
    rule.reset()
    XCTAssertFalse(rule.observe(.restMode, enabled: true, now: 303))
    _ = rule.observe(.online(), enabled: true, now: 400)
    XCTAssertFalse(rule.observe(.restMode, enabled: false, now: 401))
    XCTAssertFalse(rule.observe(.restMode, enabled: true, now: 402))
  }
  func testValidPacketIgnoresPadding() throws {
    let packet: [UInt8] = [0x6e,0x88,0x02,0x00,0x60,0x00,0x00,0x36,0x00,0x36,0xd4,0x28]
    XCTAssertEqual(try DDCPacket.input(from: packet), 54)
    XCTAssertEqual(try DDCPacket.input(from: Array(packet.prefix(11))), 54)
  }
  func testBadRepliesFailClosed() {
    let valid: [UInt8] = [0x6e,0x88,0x02,0x00,0x60,0x00,0x00,0x36,0x00,0x36,0xd4]
    for index in 0..<valid.count {
      var corrupt = valid
      corrupt[index] ^= 1
      XCTAssertThrowsError(try DDCPacket.input(from: corrupt))
    }
    for length in 0..<11 { XCTAssertThrowsError(try DDCPacket.input(from: Array(valid.prefix(length)))) }
  }
  func testPacketEncoding() {
    XCTAssertEqual(DDCPacket.getInput(), [0x82,0x01,0x60,0xdc])
    XCTAssertEqual(DDCPacket.setInput(0x36), [0x84,0x03,0x60,0x00,0x36,0xee])
  }
  func testCancelledOperationNeverCommits() {
    let operation = DisplayOperation()
    operation.cancel()
    var writes = 0
    XCTAssertThrowsError(try operation.check())
    XCTAssertThrowsError(try operation.write { writes += 1 })
    XCTAssertEqual(writes, 0)
  }
  func testPS5ParserOnlyAcceptsStatusLine() {
    XCTAssertEqual(PS5PollingPolicy.interval(for: .online()), 0.5)
    for state: DeviceStatus in [.restMode, .unavailable, .offline] {
      XCTAssertEqual(PS5PollingPolicy.interval(for: state), 2)
    }
    XCTAssertEqual(PS5Service.parse("HTTP/1.1 200 Ok\r\nhost-type:PS5\r\n"), .online())
    XCTAssertEqual(PS5Service.parse("HTTP/1.1 620 Server Standby\r\n"), .restMode)
    XCTAssertEqual(PS5Service.parse("HTTP/1.1 500 Error\r\nhost-name:200 ok"), .unavailable)
    XCTAssertEqual(PS5Service.parse("garbage status-code:620"), .unavailable)
    XCTAssertEqual(PS5Service.parse(""), .unavailable)
  }
}
