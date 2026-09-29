import AppKit
import SwiftUI

/// Content-owned navigation stays visible without an NSWindow toolbar.
struct NativePopoverContainer: View {
  @ObservedObject var appState: AppState
  var onClose: () -> Void = { NSApp.keyWindow?.close() }
  static let size = CGSize(width: 380, height: 560)
  static let cornerRadius: CGFloat = 22
  private var destination: AppDestination? { appState.navigationPath.last }
  private var title: String {
    switch destination {
    case .module(let id): return appState.module(withID: id)?.displayName ?? "裝置"
    case .settings: return "設定"
    case .diagnostics: return "診斷資訊"
    case nil: return "個人控制中心"
    }
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        if destination != nil {
          Button {
            if !appState.navigationPath.isEmpty { appState.navigationPath.removeLast() }
          } label: { Image(systemName: "chevron.left") }
            .help("返回上一頁").accessibilityLabel("返回上一頁")
            .keyboardShortcut("[", modifiers: .command)
        } else {
          Image(nsImage: ControlCenterIcon.make()).frame(width: 22, height: 20).accessibilityHidden(true)
        }
        Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
        Spacer(minLength: 4)
        if destination != nil {
          Button { appState.navigationPath.removeAll() } label: { Image(systemName: "house") }
            .help("回到首頁").accessibilityLabel("回到首頁")
        }
        PanelCloseButton(action: onClose).frame(width: 24, height: 24)
      }
      .buttonStyle(.borderless).controlSize(.small)
      .padding(.horizontal, 20).frame(height: 54)
      Divider().padding(.horizontal, 20)
      content.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .modifier(ControlCenterGlass())
    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .circular))
    .onExitCommand(perform: onClose)
  }
  @ViewBuilder private var content: some View {
    switch destination {
    case .module(let id):
      if id == "display" {
        DisplayControlsView(display: appState.displayModule, coordinator: appState.automationCoordinator)
      } else { ModuleDetailView(appState: appState, id: id) }
    case .diagnostics: DiagnosticsView(appState: appState)
    case .settings: SettingsView(appState: appState)
    case nil: DashboardView(appState: appState)
    }
  }
}

private struct ControlCenterGlass: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.glassEffect(.regular, in: RoundedRectangle(
        cornerRadius: NativePopoverContainer.cornerRadius, style: .circular))
    } else {
      content.background(.regularMaterial, in: RoundedRectangle(
        cornerRadius: NativePopoverContainer.cornerRadius, style: .circular))
    }
  }
}
