import SwiftUI

struct StatusIndicator: View {
  let color: Color

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 7, height: 7)
      .overlay(Circle().stroke(.primary.opacity(0.12), lineWidth: 0.5))
      .accessibilityHidden(true)
  }
}
