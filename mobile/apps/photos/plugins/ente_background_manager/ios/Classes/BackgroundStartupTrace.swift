import Foundation
import os

public struct BackgroundStartupTrace: Sendable {
  private static let logger = Logger(subsystem: "io.ente.background", category: "Startup")
  private let scope: String
  let invocation: String
  let startedAt: TimeInterval

  public init(
    scope: String, invocation: String = "-",
    startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) {
    self.scope = scope
    self.invocation = invocation
    self.startedAt = startedAt
  }

  public func event(_ stage: String, detail: String = "-") {
    let uptime = ProcessInfo.processInfo.systemUptime
    let elapsedMs = Int64(max(0, uptime - startedAt) * 1000)
    let uptimeMs = Int64(uptime * 1000)
    let pid = ProcessInfo.processInfo.processIdentifier
    Self.logger.notice(
      "pid=\(pid) scope=\(scope, privacy: .public) invocation=\(invocation, privacy: .public) stage=\(stage, privacy: .public) uptimeMs=\(uptimeMs) elapsedMs=\(elapsedMs) mainThread=\(Thread.isMainThread) detail=\(detail, privacy: .public)"
    )
  }

  public func measure<T>(_ stage: String, _ body: () throws -> T) rethrows -> T {
    let start = ProcessInfo.processInfo.systemUptime
    event("\(stage).begin")
    defer {
      let durationMs = Int64(max(0, ProcessInfo.processInfo.systemUptime - start) * 1000)
      event("\(stage).end", detail: "durationMs=\(durationMs)")
    }
    return try body()
  }
}
