enum PS5PollingPolicy {
  static func interval(for status: DeviceStatus) -> Double {
    if case .online = status { return 0.5 }
    return 2
  }
}
