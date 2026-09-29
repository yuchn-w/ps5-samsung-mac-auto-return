import AppKit
import SwiftUI

struct DashboardView: View {
  @ObservedObject var appState: AppState

  private var dashboardModules: [DeviceRowSnapshot] {
    ["ps5", "display", "galaxy", "sony-headphones", "adam-speakers"]
      .compactMap(appState.module(withID:))
      .map(DeviceRowSnapshot.init)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          Image(systemName: "laptopcomputer").font(.system(size: 24)).foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 1) {
            Text("Mac").font(.system(size: 13, weight: .semibold))
            Text("本機就緒").font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
        }

        SectionHeader(title: "裝置")
          .padding(.top, 2)

        VStack(spacing: 0) {
          ForEach(Array(dashboardModules.enumerated()), id: \.element.id) { index, module in
            Button {
              appState.navigationPath.append(.module(module.id))
            } label: {
              DeviceRow(module: module)
            }
            .buttonStyle(.plain)

            if index < dashboardModules.count - 1 {
              Divider().padding(.leading, 33)
            }
          }
        }

        Divider()
        AutomationSection(coordinator: appState.automationCoordinator)
        Divider()
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 16)
      }

      HStack(spacing: 12) {
        Button { appState.navigationPath.append(.diagnostics) } label: { Label("診斷", systemImage: "waveform.path.ecg") }
        Button { appState.navigationPath.append(.settings) } label: { Label("設定", systemImage: "gearshape") }
        Spacer(minLength: 4)
        Menu {
          Button("結束個人控制中心") { NSApp.terminate(nil) }
        } label: { Image(systemName: "ellipsis") }
          .menuStyle(.borderlessButton).fixedSize().help("更多選項")
      }
      .buttonStyle(.borderless).controlSize(.small)
      .font(.callout)
      .padding(.horizontal, 18)
      .padding(.vertical, 14)
    }
    .navigationTitle("")
  }
}
