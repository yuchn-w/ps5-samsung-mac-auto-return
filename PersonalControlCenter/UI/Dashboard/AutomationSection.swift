import SwiftUI

struct AutomationSection: View {
  @ObservedObject var coordinator: AutomationCoordinator

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      SectionHeader(title: "自動化")
      HStack(spacing: 9) {
        Image(systemName: "bolt.horizontal")
          .foregroundStyle(.secondary)
          .frame(width: 22)
        Text(
          coordinator.activeAutomationCount == 0
            ? "尚未啟用" : "\(coordinator.activeAutomationCount) 項已啟用"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        Spacer()
      }
      Text(coordinator.summary).font(.caption).foregroundStyle(.secondary)
      Toggle("PS5 待命後返回 Mac", isOn: Binding(
        get: { coordinator.isEnabled }, set: coordinator.setEnabled
      )).toggleStyle(.switch).controlSize(.small).disabled(!coordinator.canEnable)
    }
  }
}
