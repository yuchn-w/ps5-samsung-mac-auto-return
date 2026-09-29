import AppKit
import SwiftUI

/// A plain native close control, without SwiftUI's blue keyboard-focus bezel.
/// It remains an accessible button; Escape and keyboard activation still work.
struct PanelCloseButton: NSViewRepresentable {
  var action: () -> Void
  func makeCoordinator() -> Coordinator { Coordinator(action: action) }
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: "xmark",
      accessibilityDescription: "關閉控制中心")!, target: context.coordinator,
      action: #selector(Coordinator.close))
    button.isBordered = false
    button.focusRingType = .none
    button.imageScaling = .scaleNone
    button.contentTintColor = .secondaryLabelColor
    button.toolTip = "關閉控制中心（Esc）"
    button.setAccessibilityLabel("關閉控制中心")
    button.setContentHuggingPriority(.required, for: .horizontal)
    return button
  }
  func updateNSView(_ nsView: NSButton, context: Context) { context.coordinator.action = action }
  final class Coordinator: NSObject {
    var action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func close() { action() }
  }
}
