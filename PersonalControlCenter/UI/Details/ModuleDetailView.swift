import SwiftUI

struct ModuleDetailView: View {
  @ObservedObject var appState: AppState
  let id: String
  @AppStorage("ps5Host") private var ps5Host = ""
  private var module: (any DeviceModule)? { appState.module(withID: id) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 14) {
          Image(systemName: module?.icon ?? "questionmark.circle")
            .font(.system(size: 30)).foregroundStyle(.secondary).frame(width: 44)
          VStack(alignment: .leading, spacing: 4) {
            Text(module?.displayName ?? "裝置").font(.title3.weight(.semibold))
            Text(module?.status.displayLabel ?? "目前無法使用").font(.callout).foregroundStyle(.secondary)
          }
          Spacer()
        }
        Divider()
        if id == "ps5" {
          VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "連線資訊")
            LabeledContent("PS5 位址", value: ps5Host.isEmpty ? "尚未設定" : ps5Host)
            LabeledContent("網路連線", value: "Wi-Fi")
            LabeledContent("三星輸入", value: "HDMI 2")
            LabeledContent("Mac 輸入", value: "USB-C")
          }.font(.callout).textSelection(.enabled)
          Divider()
          AutomationSection(coordinator: appState.automationCoordinator)
          Text("收到明確待命回覆後返回 Mac；短暫未回應不代表已休眠。")
            .font(.caption).foregroundStyle(.secondary)
          Button { appState.navigationPath.append(.settings) } label: {
            Label("設定 PS5 連線位址", systemImage: "network")
          }.buttonStyle(.bordered)
        } else {
          Text("此裝置尚未完成整合，現在不會發送控制指令。")
            .font(.callout).foregroundStyle(.secondary)
          Text("可返回首頁檢查其他裝置，或在診斷頁查看目前模組狀態。")
            .font(.caption).foregroundStyle(.secondary)
          Button { appState.navigationPath.append(.diagnostics) } label: {
            Label("查看診斷資訊", systemImage: "waveform.path.ecg")
          }.buttonStyle(.bordered)
        }
      }.padding(20)
    }
  }
}
