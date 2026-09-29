import Foundation

@main enum RefreshPulseTests {
  static func main() throws {
    let mode = ModeRecord(id: 71, width: 1920, height: 1080, pixelWidth: 3840,
      pixelHeight: 2160, hz: 240, flags: 33554439, usable: true)
    let ext = ScreenRecord(id: 2, uuid: "00000000-0000-4000-8000-000000000001",
      vendor: 19501, model: 31508, builtIn: false, active: true, mirrored: false,
      main: true, x: 0, y: 0, rotation: 0, mode: mode)
    var builtin = ext
    builtin.id = 1; builtin.uuid = "00000000-0000-4000-8000-000000000002"
    builtin.builtIn = true; builtin.main = false
    let original = [builtin, ext]
    var temp = original; temp[1].mode.id = 73; temp[1].mode.hz = 120; temp[1].mode.flags &= ~UInt32(4)
    let plan = PulsePlan(original: original, temporary: temp, uuid: ext.uuid)
    var checks = 0
    func check(_ good: Bool, _ name: String) { precondition(good, name); checks += 1; print("PASS: \(name)") }
    try plan.validate()
    var writes = 0
    let unchanged = try RecoveryOnce().run(original, plan: plan) { writes += 1 }
    check(unchanged == .unchanged && writes == 0, "no write if original already present")
    let owner = RecoveryOnce()
    let restored = try owner.run(temp, plan: plan) { writes += 1 }
    check(restored == .restore && writes == 1, "one restore from owned temporary setup")
    do { _ = try owner.run(temp, plan: plan) { writes += 1 } } catch {}
    check(writes == 1, "never restore twice")
    let failed = RecoveryOnce(); var rejected = false
    do { _ = try failed.run(temp, plan: plan) { writes += 1; throw ProbeError("mock failure") } } catch { rejected = true }
    do { _ = try failed.run(temp, plan: plan) { writes += 1 } } catch {}
    check(rejected && writes == 2, "failed restore not retried")
    for (name, mutate) in [
      ("different UUID", { (s: inout [ScreenRecord]) in s[1].uuid = UUID().uuidString }),
      ("user chose 60 Hz", { (s: inout [ScreenRecord]) in s[1].mode.hz = 60 }),
      ("built-in moved", { (s: inout [ScreenRecord]) in s[0].x = 200 }),
      ("target mirrored", { (s: inout [ScreenRecord]) in s[1].mirrored = true }),
      ("target removed", { (s: inout [ScreenRecord]) in s.removeLast() })
    ] {
      var changed = temp; mutate(&changed)
      let beforeWrites = writes
      let decision = try RecoveryOnce().run(changed, plan: plan) { writes += 1 }
      check(decision == .refuse && writes == beforeWrites, "refuse \(name)")
    }
    for (name, mutate) in [
      ("geometry change", { (s: inout [ScreenRecord]) in s[1].mode.width = 2560 }),
      ("other flags", { (s: inout [ScreenRecord]) in s[1].mode.flags ^= 8 }),
      ("arrangement change", { (s: inout [ScreenRecord]) in s[1].x = 99 }),
      ("no built-in", { (s: inout [ScreenRecord]) in s.removeFirst() }),
      ("unusable mode", { (s: inout [ScreenRecord]) in s[1].mode.usable = false })
    ] {
      var changed = temp; mutate(&changed); var refused = false
      do { try PulsePlan(original: original, temporary: changed, uuid: ext.uuid).validate() } catch { refused = true }
      check(refused, "reject plan \(name)")
    }
    print("\(checks) checks passed; fake data only, no hardware writes")
  }
}
