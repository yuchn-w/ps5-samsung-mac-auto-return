import Foundation

@MainActor
protocol DeviceModule: AnyObject, Identifiable {
  var id: String { get }
  var displayName: String { get }
  var icon: String { get }
  var status: DeviceStatus { get }
  var isAvailable: Bool { get }
  var detailDestination: AppDestination { get }
  var onStatusChange: (() -> Void)? { get set }

  func start()
  func stop()
}
