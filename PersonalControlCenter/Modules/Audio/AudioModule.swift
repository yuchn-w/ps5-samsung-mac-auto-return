final class SonyHeadphonesModule: PlaceholderModule {
  init() {
    super.init(
      id: "sony-headphones", displayName: "Sony WH-1000XM5", icon: "headphones",
      logger: AppLogger.audio)
  }
}

final class AdamSpeakersModule: PlaceholderModule {
  init() {
    super.init(
      id: "adam-speakers", displayName: "ADAM D3V", icon: "speaker.wave.2",
      logger: AppLogger.audio)
  }
}
