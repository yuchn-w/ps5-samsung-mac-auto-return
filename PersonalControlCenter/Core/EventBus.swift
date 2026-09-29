import Foundation

final class EventBus: @unchecked Sendable {
  static let shared = EventBus()
  private let center = NotificationCenter()

  private init() {}

  func post(_ event: AppEvent) {
    center.post(name: .appEvent, object: event)
  }

  @discardableResult
  func observe(using handler: @escaping @Sendable (AppEvent) -> Void) -> NSObjectProtocol {
    center.addObserver(forName: .appEvent, object: nil, queue: .main) { notification in
      guard let event = notification.object as? AppEvent else { return }
      handler(event)
    }
  }

  func removeObserver(_ observer: NSObjectProtocol) {
    center.removeObserver(observer)
  }
}
