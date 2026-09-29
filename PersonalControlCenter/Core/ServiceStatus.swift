enum ServiceStatus: String, Sendable {
  case idle = "Idle"
  case starting = "Starting"
  case running = "Running"
  case stopped = "Stopped"
  case failed = "Failed"
}
