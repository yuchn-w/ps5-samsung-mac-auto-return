import SwiftUI

struct SectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.caption)
      .fontWeight(.semibold)
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
      .tracking(0.35)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
