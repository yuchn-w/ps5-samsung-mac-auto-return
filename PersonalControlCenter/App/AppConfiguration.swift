import Foundation

enum AppConfiguration {
  static let displayName =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
    ?? "Personal Control Center"
  static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "org.sceneharbor.PersonalControlCenter"
}
