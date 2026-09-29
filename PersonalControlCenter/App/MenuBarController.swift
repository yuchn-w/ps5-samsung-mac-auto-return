import AppKit
import SwiftUI

private final class ControlCenterPanel: NSPanel {
  var dismiss: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  override func cancelOperation(_ sender: Any?) { dismiss?() }
}

private final class TransparentPanelHostingView<Content: View>: NSHostingView<Content> {
  override var isOpaque: Bool { false }
  override func layout() {
    super.layout()
    // Match the actual compositing boundary to the glass, not only its artwork.
    // SwiftUI layout can update the hosting layer, so keep this invariant here.
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.cornerRadius = NativePopoverContainer.cornerRadius
    layer?.cornerCurve = .circular
    layer?.masksToBounds = true
  }
}

/// Only anchoring/dismissal crosses into AppKit. A transparent panel prevents
/// NSPopover's backing material from stacking underneath the SwiftUI glass.
@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
  private let statusItem: NSStatusItem
  private let panel: ControlCenterPanel
  private let appState: AppState
  private var preferenceObserver: NSObjectProtocol?
  private var outsideClickMonitor: Any?
  private var localClickMonitor: Any?

  init(appState: AppState) {
    self.appState = appState
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    panel = ControlCenterPanel(contentRect: NSRect(origin: .zero, size: NativePopoverContainer.size),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    super.init()

    if let button = statusItem.button {
      button.image = ControlCenterIcon.make()
      button.imagePosition = .imageOnly
      button.toolTip = "個人控制中心：電腦與裝置控制"
      button.setAccessibilityLabel("個人控制中心")
      button.target = self
      button.action = #selector(togglePanel(_:))
    }

    panel.isOpaque = false
    panel.backgroundColor = .clear
    // Borderless NSWindow shadows can retain a rectangular silhouette. Let the
    // single glass surface supply depth, without a second window shadow layer.
    panel.hasShadow = false
    panel.level = .popUpMenu
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.delegate = self
    panel.dismiss = { [weak self] in self?.closePanel() }
    let hosting = TransparentPanelHostingView(rootView: NativePopoverContainer(appState: appState,
      onClose: { [weak self] in self?.closePanel() }))
    hosting.wantsLayer = true
    panel.contentView = hosting
    panel.initialFirstResponder = nil

    applyStatusTextPreference()
    preferenceObserver = NotificationCenter.default.addObserver(
      forName: .statusTextPreferenceChanged,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.applyStatusTextPreference() }
    }
  }

  deinit {
    if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
  }

  @objc private func togglePanel(_ sender: Any?) {
    if panel.isVisible { closePanel(); return }
    showPanel()
  }

  func showPanel(on preferredScreen: NSScreen? = nil) {
    if panel.isVisible { closePanel() }
    guard let button = statusItem.button, let window = button.window else { return }
    appState.navigationPath.removeAll()
    let anchor: NSRect
    if let preferredScreen {
      anchor = NSRect(x: preferredScreen.visibleFrame.maxX - 40,
                      y: preferredScreen.visibleFrame.maxY + 7, width: 22, height: 20)
    } else { anchor = window.convertToScreen(button.convert(button.bounds, to: nil)) }
    let visible = (preferredScreen ?? window.screen ?? NSScreen.main)?.visibleFrame ?? anchor
    let x = min(max(anchor.midX - NativePopoverContainer.size.width / 2, visible.minX + 8),
                visible.maxX - NativePopoverContainer.size.width - 8)
    let y = max(visible.minY + 8, anchor.minY - NativePopoverContainer.size.height - 7)
    panel.setFrameOrigin(NSPoint(x: x, y: y))
    // The on-demand SwiftUI scene hosts the same controls. Do not leave that
    // rectangular window underneath the rounded status-item panel.
    for sceneWindow in NSApp.windows where sceneWindow !== panel &&
      sceneWindow.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
      sceneWindow.orderOut(nil)
    }
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(panel)
    panel.invalidateShadow()
    installDismissalMonitors()
    AppLogger.app.info("Control panel opened at home; single glass surface")
  }

  private func installDismissalMonitors() {
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] _ in Task { @MainActor in self?.closePanel() }
    }
    localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] event in
      MainActor.assumeIsolated {
        if let self, event.window !== self.panel, event.window !== self.statusItem.button?.window {
          self.closePanel()
        }
      }
      return event
    }
  }
  private func closePanel() {
    panel.orderOut(nil)
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor); self.outsideClickMonitor = nil }
    if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor); self.localClickMonitor = nil }
  }
  func windowDidResignKey(_ notification: Notification) { closePanel() }

  private func applyStatusTextPreference() {
    let showText = UserDefaults.standard.bool(forKey: SettingsKeys.showStatusText)
    statusItem.length = showText ? NSStatusItem.variableLength : NSStatusItem.squareLength
    statusItem.button?.title = showText ? " 控制中心" : ""
  }
}
