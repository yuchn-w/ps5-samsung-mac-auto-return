import AppKit
import SwiftUI

struct DiagnosticsView: View {
  @ObservedObject var appState: AppState
  @State private var copied = false

  var body: some View {
    ScrollView {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "App")
        diagnosticRow("版本", value: version)
        diagnosticRow("組建", value: build)
        diagnosticRow("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
        diagnosticRow("架構", value: architecture)
      }
      Divider()
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "模組")
        ForEach(appState.modules, id: \.id) { module in
          diagnosticRow(module.displayName, value: module.status.displayLabel)
        }
        diagnosticRow("自動化", value: appState.automationCoordinator.status.rawValue)
      }
      Divider()
      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DiagnosticsReport.make(for: appState), forType: .string)
        copied = true
      } label: {
        Label(
          copied ? "已複製" : "複製診斷資訊", systemImage: copied ? "checkmark" : "doc.on.doc")
      }.buttonStyle(.bordered)
    }.padding(20)
    }
  }

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
  }
  private var build: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
  }
  private var architecture: String {
    #if arch(arm64)
      return "Apple Silicon (arm64)"
    #else
      return "Intel (x86_64)"
    #endif
  }

  private func diagnosticRow(_ label: String, value: String) -> some View {
    LabeledContent(label, value: value)
      .font(.callout)
  }
}
