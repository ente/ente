import Foundation

final class ForegroundHeartbeat {
  private let defaults = UserDefaults.standard
  private let queue = DispatchQueue(
    label: "io.ente.frame.foreground-heartbeat",
    qos: .utility
  )
  private var timer: DispatchSourceTimer?

  func start() {
    queue.async {
      if self.timer != nil {
        return
      }
      let timer = DispatchSource.makeTimerSource(queue: self.queue)
      timer.schedule(
        deadline: .now(),
        repeating: self.heartbeatInterval,
        leeway: .milliseconds(100)
      )
      timer.setEventHandler { [weak self] in
        self?.writeNativeHeartbeat()
      }
      timer.resume()
      self.timer = timer
    }
  }

  func stop() {
    queue.async {
      self.timer?.cancel()
      self.timer = nil
    }
  }

  private func writeNativeHeartbeat() {
    defaults.set(
      Int64(Date().timeIntervalSince1970 * 1_000_000),
      forKey: nativeForegroundHeartbeatKey
    )
  }

  private let nativeForegroundHeartbeatKey = "flutter.native_fg_task_hb_time"
  private let heartbeatInterval: DispatchTimeInterval = .seconds(1)
}
