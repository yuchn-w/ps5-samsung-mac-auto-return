import SwiftUI

enum DeviceStatus: Equatable, Sendable {
  case notConfigured
  case unavailable
  case offline
  case restMode
  case online(detail: String? = nil)

  var label: String {
    switch self {
    case .notConfigured: return "Not configured"
    case .unavailable: return "Unavailable"
    case .offline: return "未回應（電源狀態未知）"
    case .restMode: return "待命模式"
    case .online(let detail): return detail ?? "Online"
    }
  }

  var indicatorColor: Color {
    switch self {
    case .online: return .green
    case .offline, .restMode: return .secondary
    case .notConfigured, .unavailable: return .clear
    }
  }
}
