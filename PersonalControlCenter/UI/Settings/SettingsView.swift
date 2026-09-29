import SwiftUI

struct SettingsView: View {
  @ObservedObject var appState: AppState
  @AppStorage(SettingsKeys.showStatusText) private var showStatusText = false
  @AppStorage("ps5Host") private var ps5Host = ""
  @AppStorage("refreshReturnTargetUUID") private var targetUUID = ""

  var body: some View {
    ScrollView {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "一般")
        LabeledContent("登入時啟動") {
          Text("尚未提供")
            .foregroundStyle(.secondary)
        }
        Toggle("在狀態列顯示名稱", isOn: $showStatusText).toggleStyle(.switch).controlSize(.small)
      }
      Divider()
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "PS5 連線")
        TextField("IP 位址或主機名稱", text: $ps5Host).textFieldStyle(.roundedBorder)
        Text("僅用於區域網路狀態偵測；變更位址後會重新監測。")
          .font(.caption).foregroundStyle(.secondary)
      }
      Divider()
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "返回目標螢幕")
        TextField("本機螢幕 UUID（由唯讀 preflight 取得）", text: $targetUUID)
          .textFieldStyle(.roundedBorder)
        Text("請先依 README 完成唯讀檢查及單次現場測試。更改目標會停用自動返回，需重新確認後開啟。")
          .font(.caption).foregroundStyle(.secondary)
      }
      Divider()
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "診斷")
        Button {
          appState.navigationPath.append(.diagnostics)
        } label: {
          Label("開啟診斷資訊", systemImage: "waveform.path.ecg")
        }
      }
      Divider()
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "關於")
        LabeledContent("版本", value: version)
        Text("Personal Control Center").font(.caption).foregroundStyle(.secondary)
      }
    }.padding(20).buttonStyle(.bordered)
    }
    .onChange(of: showStatusText) { _ in
      NotificationCenter.default.post(name: .statusTextPreferenceChanged, object: nil)
    }
    .onChange(of: targetUUID) { _ in appState.automationCoordinator.setEnabled(false) }
  }

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
  }
}
