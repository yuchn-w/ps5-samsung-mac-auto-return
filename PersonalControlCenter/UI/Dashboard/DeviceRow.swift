import SwiftUI

struct DeviceRow: View {
  let module: DeviceRowSnapshot

  var body: some View {
    HStack(spacing: 11) {
      Image(systemName: module.icon)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 22)

      VStack(alignment: .leading, spacing: 2) {
        Text(module.displayName)
          .font(.system(size: 13, weight: .medium))
          .lineLimit(1)
        Text(module.status.displayLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      if module.indicatorIsVisible {
        StatusIndicator(color: module.status.indicatorColor)
      }
      Image(systemName: "chevron.right")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .contentShape(Rectangle())
    .padding(.vertical, 8)
  }
}

extension DeviceStatus {
  var displayLabel: String {
    switch self {
    case .notConfigured: return "尚未設定"
    case .unavailable: return "目前無法使用"
    case .online(let detail): return detail ?? "已連線"
    default: return label
    }
  }
}

struct DeviceRowSnapshot: Identifiable {
  let id: String
  let displayName: String
  let icon: String
  let status: DeviceStatus

  @MainActor init(_ module: any DeviceModule) {
    id = module.id
    displayName = module.displayName
    icon = module.icon
    status = module.status
  }

  fileprivate var indicatorIsVisible: Bool {
    switch status {
    case .online, .offline, .restMode: return true
    case .notConfigured, .unavailable: return false
    }
  }
}
