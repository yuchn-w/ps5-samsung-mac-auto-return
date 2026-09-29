import Foundation
import Network

final class PS5Service: @unchecked Sendable {
  private let queue = DispatchQueue(label: "org.sceneharbor.PersonalControlCenter.ps5")

  func probe(host: String, completion: @escaping @Sendable (Result<DeviceStatus, Error>) -> Void) {
    guard let port = NWEndpoint.Port(rawValue: 9302) else { return }
    let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .udp)
    let resultGate = ResultGate(completion: completion)

    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        let request = "SRCH * HTTP/1.1\r\ndevice-discovery-protocol-version:00030010\r\n\r\n"
        connection.send(
          content: Data(request.utf8),
          completion: .contentProcessed { error in
            if let error {
              resultGate.finish(.failure(error))
              connection.cancel()
              return
            }
            connection.receiveMessage { data, _, _, error in
              defer { connection.cancel() }
              if let error {
                resultGate.finish(.failure(error))
              } else if let data, let response = String(data: data, encoding: .utf8) {
                resultGate.finish(.success(Self.parse(response)))
              } else {
                resultGate.finish(.failure(ProbeError.emptyResponse))
              }
            }
          })
      case .failed(let error):
        resultGate.finish(.failure(error))
        connection.cancel()
      default:
        break
      }
    }

    connection.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 2) {
      resultGate.finish(.failure(ProbeError.timedOut))
      connection.cancel()
    }
  }

  static func parse(_ response: String) -> DeviceStatus {
    let fields = response.split(whereSeparator: \.isNewline).first?
      .split(separator: " ", omittingEmptySubsequences: true) ?? []
    guard fields.count >= 2, fields[0].uppercased() == "HTTP/1.1" else { return .unavailable }
    if fields[1] == "200" {
      return .online()
    }
    if fields[1] == "620" {
      return .restMode
    }
    return .unavailable
  }
}

private enum ProbeError: Error {
  case emptyResponse
  case timedOut
}

private final class ResultGate: @unchecked Sendable {
  private let lock = NSLock()
  private var finished = false
  private let completion: @Sendable (Result<DeviceStatus, Error>) -> Void

  init(completion: @escaping @Sendable (Result<DeviceStatus, Error>) -> Void) {
    self.completion = completion
  }

  func finish(_ result: Result<DeviceStatus, Error>) {
    lock.lock()
    guard !finished else {
      lock.unlock()
      return
    }
    finished = true
    lock.unlock()
    completion(result)
  }
}
