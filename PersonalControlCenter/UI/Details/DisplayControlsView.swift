import SwiftUI

struct DisplayControlsView: View {
  @ObservedObject var display: DisplayModule
  @ObservedObject var coordinator: AutomationCoordinator
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text("PS5：HDMI 2 · Mac：USB-C").font(.subheadline)
        Toggle("PS5 待命後自動返回 Mac", isOn: Binding(
          get: { coordinator.isEnabled }, set: coordinator.setEnabled
        )).toggleStyle(.switch).controlSize(.small).disabled(!coordinator.canEnable)
        Text("使用 240 → 120 → 240 Hz。PS5 開機期間每 0.5 秒偵測；收到明確待命回覆後觸發一次。")
          .font(.caption).foregroundStyle(.secondary)
        Text(coordinator.summary).font(.callout).textSelection(.enabled)
        if let duration = coordinator.lastDuration {
          Text("最近一次執行：\(duration, specifier: "%.2f") 秒").font(.caption).foregroundStyle(.secondary)
        }
        Text("已實測可返回 Mac；黑畫面次數與無縫程度尚未驗證。此策略不操作 HDR 開關。")
          .font(.caption).foregroundStyle(.secondary)
        if coordinator.isSwitching { ProgressView().controlSize(.small) }
        Divider()
        DisclosureGroup("進階 DDC 診斷（先前測試未成功）") {
        VStack(alignment: .leading, spacing: 14) {
        LabeledContent("目前輸入讀值", value: display.currentInput)
        Text(display.lastResult).font(.callout).textSelection(.enabled)
        if let date = display.resultDate {
          Text(date, style: .time).font(.caption).foregroundStyle(.secondary)
        }
        Divider()
        Text("1. 三星目前顯示 Mac 時").font(.headline)
        Button("記錄目前 Mac 輸入") { display.captureMacInput() }.disabled(display.isBusy)
        Text("候選值：\(display.candidate?.hexInput ?? "尚未記錄")；不套用通用 USB-C 代碼。")
          .font(.caption).foregroundStyle(.secondary)
        Text("2. 將三星切到 HDMI 2 後").font(.headline)
        Button("測試返回 Mac") { display.returnToMac() }
          .disabled(display.isBusy || display.candidate == nil)
        Text("請在 Mac 內建螢幕操作。只有來源讀值確實改變並讀回相符，才可確認畫面。")
          .font(.caption).foregroundStyle(.secondary)
        Button("已看到三星返回 Mac 畫面") { display.confirmVisibleReturn() }
          .disabled(!display.canConfirm || display.isBusy)
        Text("實際畫面確認：\(display.confirmations)/2 次")
          .font(.caption).foregroundStyle(.secondary)
        Divider()
        Text("這些 DDC 校準操作不會解鎖或觸發更新率自動返回。未回應不視為 PS5 休眠。")
          .font(.caption).foregroundStyle(.secondary)
        Button("重新讀取螢幕") { display.refresh() }.disabled(display.isBusy)
        if display.isBusy { ProgressView().controlSize(.small) }
        }.padding(.top, 12).buttonStyle(.bordered).controlSize(.small)
        }
      }.padding(18)
    }.navigationTitle("返回 Mac")
  }
}
