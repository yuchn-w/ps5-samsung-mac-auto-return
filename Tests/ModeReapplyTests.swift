import Foundation

final class FakeReapplyDriver: ReapplyDriver {
  var snapshots: [[ScreenRecord]]
  var writes = 0
  var failWrite = false
  init(_ snapshots: [[ScreenRecord]]) { self.snapshots = snapshots }
  func capture() throws -> [ScreenRecord] {
    guard !snapshots.isEmpty else { throw ProbeError("missing mock snapshot") }
    return snapshots.count > 1 ? snapshots.removeFirst() : snapshots[0]
  }
  func commitSameMode(expected: [ScreenRecord], target: ScreenRecord) throws {
    writes += 1
    if failWrite { throw ProbeError("mock write rejected") }
  }
}

@main
enum ModeReapplyTests {
  static func main() throws {
    let mode = ModeRecord(id: 71, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160,
                          hz: 240, flags: 33554439, usable: true)
    let external = ScreenRecord(id: 2, uuid: "00000000-0000-4000-8000-000000000001", vendor: 19501,
                                model: 31508, builtIn: false, active: true, mirrored: false, main: true,
                                x: 0, y: 0, rotation: 0, mode: mode)
    var builtin = external
    builtin.id = 1; builtin.uuid = "00000000-0000-4000-8000-000000000002"
    builtin.vendor = 1552; builtin.model = 41058; builtin.builtIn = true; builtin.main = false
    let normal = [builtin, external]
    let request = ReapplyRequest(uuid: external.uuid, expectedMode: mode.fingerprint,
                                 hdrBaseline: "off", hdmi2Confirmed: true)
    var tests = 0
    func check(_ condition: Bool, _ name: String) {
      if !condition { fatalError("FAIL: \(name)") }
      tests += 1; print("PASS: \(name)")
    }
    func rejected(_ name: String, _ snapshots: [[ScreenRecord]], _ req: ReapplyRequest = request) {
      let driver = FakeReapplyDriver(snapshots)
      let engine = OneShotReapply()
      var stopped = false
      do { _ = try engine.run(driver: driver, request: req) } catch { stopped = true }
      check(stopped && driver.writes == 0, name)
    }
    rejected("empty inventory", [[]])
    rejected("no built-in", [[external]])
    rejected("no external", [[builtin]])
    rejected("multiple external", [[builtin, external, external]])
    var changed = external
    changed.model = 999
    rejected("wrong model", [[builtin, changed]])
    changed = external; changed.mirrored = true
    rejected("mirror mode", [[builtin, changed]])
    changed = external; changed.active = false
    rejected("inactive external", [[builtin, changed]])
    changed = builtin; changed.active = false
    rejected("inactive built-in", [[changed, external]])
    changed = external; changed.mode.usable = false
    rejected("unusable desktop mode", [[builtin, changed]])
    changed = external; changed.mode.hz = .nan
    rejected("invalid refresh rate", [[builtin, changed]])
    var req = request; req.uuid = UUID().uuidString
    rejected("wrong UUID", [normal], req)
    req = request; req.expectedMode = "stale-mode"
    rejected("stale mode fingerprint", [normal], req)
    req = request; req.hdmi2Confirmed = false
    rejected("missing physical source confirmation", [normal], req)
    req = request; req.hdrBaseline = "unknown"
    rejected("unknown HDR baseline", [normal], req)
    changed = external; changed.mode.hz = 120
    rejected("mode changes between preflights", [normal, [builtin, changed]])
    changed = builtin; changed.x = 200
    rejected("built-in arrangement changes between preflights", [normal, [changed, external]])
    let success = FakeReapplyDriver([normal])
    let engine = OneShotReapply()
    let result = try engine.run(driver: success, request: request)
    check(result == normal && success.writes == 1, "exactly one mock commit")
    do { _ = try engine.run(driver: success, request: request) } catch {}
    check(success.writes == 1, "second invocation refused")
    let failure = FakeReapplyDriver([normal]); failure.failWrite = true
    let failedEngine = OneShotReapply()
    do { _ = try failedEngine.run(driver: failure, request: request) } catch {}
    do { _ = try failedEngine.run(driver: failure, request: request) } catch {}
    check(failure.writes == 1, "write failure never retried")
    changed = external; changed.mode.hz = 120
    let drift = FakeReapplyDriver([normal, normal, [builtin, changed]])
    var driftStopped = false
    do { _ = try OneShotReapply().run(driver: drift, request: request) } catch { driftStopped = true }
    check(driftStopped && drift.writes == 1, "post-commit drift does not trigger restore writes")
    print("\(tests) tests passed; no real display APIs or hardware commands used.")
  }
}
