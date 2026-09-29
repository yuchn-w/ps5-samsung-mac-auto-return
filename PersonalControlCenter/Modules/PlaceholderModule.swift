import Foundation
import OSLog

@MainActor
class PlaceholderModule: DeviceModule {
  let id: String
  let displayName: String
  let icon: String
  let detailDestination: AppDestination
  private let logger: Logger
  private(set) var status: DeviceStatus = .notConfigured
  var onStatusChange: (() -> Void)?
  var isAvailable: Bool { false }

  init(id: String, displayName: String, icon: String, logger: Logger) {
    self.id = id
    self.displayName = displayName
    self.icon = icon
    self.detailDestination = .module(id)
    self.logger = logger
  }

  func start() { logger.debug("Placeholder module started") }
  func stop() { logger.debug("Placeholder module stopped") }

  func updateStatus(_ newStatus: DeviceStatus) {
    guard status != newStatus else { return }
    status = newStatus
    onStatusChange?()
  }
}
