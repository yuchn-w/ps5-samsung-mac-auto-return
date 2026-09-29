final class ClipboardModule: PlaceholderModule {
  init() {
    super.init(
      id: "clipboard", displayName: "Mac ↔ Galaxy Clipboard", icon: "clipboard",
      logger: AppLogger.clipboard)
  }
}
