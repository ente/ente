import BackgroundTasks
@preconcurrency import Flutter
import Foundation
import UIKit
import os

@MainActor
final class BackgroundRuntime: NSObject {
  static let shared = BackgroundRuntime()
  private static let logger = Logger(subsystem: "io.ente.background", category: "BackgroundManager")
  private var configuration = StoredConfiguration.load()
  private var isAllowed: () -> Bool = { false }
  private var registrant: ((FlutterPluginRegistry) -> Void)?
  private let observers = NSHashTable<BackgroundManagerPlugin>.weakObjects()
  private var registrations: [String: Bool] = [:]
  private var active: Run?
  private var waiting: Run?
  private var isForeground = false
  private var installed = false
  private var reconciling = false
  private var scheduleRevision = 0
  private var configurationResults: [FlutterResult] = []

  private final class Run {
    let task: BGTask
    let configuration: TaskConfiguration
    let startedAt: TimeInterval
    let invocation: String
    let trace: BackgroundStartupTrace
    var engine: FlutterEngine?
    var channel: FlutterMethodChannel?
    var ready = false
    var retiring = false
    var stopReason: String?
    var budgetTimer: DispatchWorkItem?
    var foregroundTimer: DispatchWorkItem?
    var stopResults: [FlutterResult] = []

    init(task: BGTask, configuration: TaskConfiguration, trace: BackgroundStartupTrace) {
      self.task = task
      self.configuration = configuration
      self.startedAt = trace.startedAt
      self.invocation = trace.invocation
      self.trace = trace
    }
  }

  func install(
    isEnabled: @escaping () -> Bool,
    registrant: @escaping (FlutterPluginRegistry) -> Void
  ) {
    isAllowed = isEnabled
    self.registrant = registrant
    guard !installed else { return }
    installed = true
    isForeground = UIApplication.shared.applicationState == .active
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(foreground), name: UIApplication.willEnterForegroundNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification,
      object: nil)
  }

  func register(identifier: String, processing: Bool) -> Bool {
    if let existing = registrations[identifier] { return existing == processing }
    let trace = BackgroundStartupTrace(scope: identifier)
    let registered = trace.measure("task.register") {
      BGTaskScheduler.shared.register(
        forTaskWithIdentifier: identifier, using: .main
      ) { task in
        let startedAt = ProcessInfo.processInfo.systemUptime
        let deliveryTrace = BackgroundStartupTrace(
          scope: task.identifier, invocation: UUID().uuidString, startedAt: startedAt)
        deliveryTrace.event("task.delivered")
        MainActor.assumeIsolated {
          self.deliver(task, trace: deliveryTrace)
        }
      }
    }
    trace.event("task.register.result", detail: "registered=\(registered)")
    if registered {
      registrations[identifier] = processing
    } else {
      report(identifier: identifier, outcome: "failed", reason: "registration")
    }
    return registered
  }

  func attach(_ plugin: BackgroundManagerPlugin) {
    observers.add(plugin)
  }

  func detach(_ plugin: BackgroundManagerPlugin) {
    observers.remove(plugin)
  }

  @objc private func foreground() {
    isForeground = true
    if let run = waiting { finishWaiting(run, outcome: "stopped", reason: "foreground") }
    if let run = active { stop(run, reason: "foreground") }
  }

  @objc private func background() {
    isForeground = false
  }

  func requestStop(result: FlutterResult? = nil) {
    if let run = waiting { finishWaiting(run, outcome: "stopped", reason: "requested") }
    guard let run = active else {
      result?(nil)
      return
    }
    if let result { run.stopResults.append(result) }
    stop(run, reason: "requested")
  }

  func configure(_ data: [String: Any]?, result: @escaping FlutterResult) {
    guard let data, let callback = data["callbackHandle"] as? NSNumber,
      let tasks = data["tasks"] as? [[String: Any]], let enabled = data["enabled"] as? Bool,
      installed
    else {
      result(
        FlutterError(
          code: "configuration", message: "Background manager was not installed at launch",
          details: nil))
      return
    }
    do {
      let parsed = try tasks.map { try TaskConfiguration($0, callbackHandle: callback.int64Value) }
      guard Set(parsed.map(\.identifier)).count == parsed.count else {
        throw TaskConfiguration.ConfigurationError.duplicateIdentifier
      }
      for task in parsed {
        guard registrations[task.identifier] == (task.kind == "processing") else {
          throw TaskConfiguration.ConfigurationError.unregisteredIdentifier
        }
      }
      guard parsed.filter({ $0.kind == "refresh" }).count <= 1 else {
        result(
          FlutterError(
            code: "configuration", message: "iOS supports at most one refresh task", details: nil))
        return
      }
      guard parsed.filter({ $0.kind == "processing" }).count <= 10 else {
        result(
          FlutterError(
            code: "configuration", message: "iOS supports at most ten processing tasks",
            details: nil))
        return
      }
      let identifiers = enabled ? Set(parsed.map(\.identifier)) : []
      let owned = Set(registrations.keys)
        .union(configuration.tasks.map(\.identifier))
        .union((configuration.submitted ?? []).map(\.identifier))
      for identifier in owned.subtracting(identifiers) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
      }
      let next = StoredConfiguration(
        enabled: enabled, tasks: parsed,
        submitted: configuration.submitted?.filter { identifiers.contains($0.identifier) })
      try next.save()
      configuration = next
      if let run = waiting, !identifiers.contains(run.configuration.identifier) {
        finishWaiting(run, outcome: "skipped", reason: "disabled")
      }
      if !enabled { requestStop() }
      configurationResults.append(result)
      reconcile()
    } catch {
      result(FlutterError(code: "configuration", message: String(describing: error), details: nil))
    }
  }

  private func reconcile() {
    guard !reconciling else { return }
    reconciling = true
    let revision = scheduleRevision
    BGTaskScheduler.shared.getPendingTaskRequests { requests in
      DispatchQueue.main.async {
        guard revision == self.scheduleRevision else {
          self.reconciling = false
          self.reconcile()
          return
        }
        let pending = Dictionary(
          requests.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let desired = self.configuration.enabled ? self.configuration.tasks : []
        let submitted = self.configuration.submitted ?? []
        var failure: Error?
        for task in desired {
          if pending[task.identifier] != nil,
            submitted.contains(where: { $0.hasSameSchedule(as: task) })
          {
            continue
          }
          do {
            try self.submit(task, delayMs: task.initialDelayMs)
            try self.recordSubmitted(task)
          } catch {
            failure = error
            self.report(
              identifier: task.identifier, outcome: "failed", reason: "schedule",
              error: String(describing: error))
          }
        }
        self.reconciling = false
        let results = self.configurationResults
        self.configurationResults.removeAll()
        for result in results {
          if let failure {
            result(
              FlutterError(code: "schedule", message: String(describing: failure), details: nil))
          } else {
            result(nil)
          }
        }
      }
    }
  }

  private func submit(_ task: TaskConfiguration, delayMs: Int64) throws {
    let request: BGTaskRequest
    if task.kind == "processing" {
      let processing = BGProcessingTaskRequest(identifier: task.identifier)
      processing.requiresNetworkConnectivity = task.requiresNetwork
      processing.requiresExternalPower = task.requiresCharging
      request = processing
    } else {
      request = BGAppRefreshTaskRequest(identifier: task.identifier)
    }
    request.earliestBeginDate = Date(timeIntervalSinceNow: Double(delayMs) / 1000)
    try BGTaskScheduler.shared.submit(request)
  }

  private func recordSubmitted(_ task: TaskConfiguration) throws {
    if (configuration.submitted ?? []).contains(task) { return }
    var next = configuration
    next.submitted = (next.submitted ?? []).filter { $0.identifier != task.identifier } + [task]
    try next.save()
    configuration = next
  }

  func scheduledTasks(_ result: @escaping FlutterResult) {
    BGTaskScheduler.shared.getPendingTaskRequests { requests in
      DispatchQueue.main.async {
        let pending = Set(requests.map(\.identifier))
        result(
          Dictionary(
            uniqueKeysWithValues: self.configuration.tasks.map {
              ($0.identifier, pending.contains($0.identifier))
            }))
      }
    }
  }

  private func deliver(_ task: BGTask, trace: BackgroundStartupTrace) {
    scheduleRevision += 1
    guard configuration.enabled,
      let policy = configuration.tasks.first(where: { $0.identifier == task.identifier })
    else {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: task.identifier)
      trace.event("task.skipped", detail: "reason=disabled")
      report(identifier: task.identifier, outcome: "skipped", reason: "disabled")
      task.setTaskCompleted(success: true)
      trace.event("task.completed", detail: "success=true")
      return
    }
    do {
      try trace.measure("task.reschedule") {
        try submit(policy, delayMs: policy.frequencyMs)
        try recordSubmitted(policy)
      }
    } catch {
      trace.event("task.reschedule.failed")
      report(
        identifier: task.identifier, outcome: "failed", reason: "schedule",
        error: String(describing: error))
    }
    if isAllowed(), !isForeground, UIApplication.shared.applicationState == .background,
      policy.kind == "processing", let occupant = active,
      occupant.configuration.kind == "refresh", !occupant.retiring, waiting == nil,
      !["foreground", "requested", "system"].contains(occupant.stopReason ?? "")
    {
      let run = Run(task: task, configuration: policy, trace: trace)
      waiting = run
      observeExpiration(run)
      trace.event("task.waitingForRefresh")
      Self.logger.info("\(policy.identifier, privacy: .public): waiting for refresh")
      if let budget = policy.runBudgetMs {
        let remaining = budget - elapsed(run)
        if remaining <= 0 {
          finishWaiting(run, outcome: "skipped", reason: "waitBudget")
        } else {
          let timer = DispatchWorkItem { [weak run] in
            guard let run else { return }
            self.finishWaiting(run, outcome: "skipped", reason: "waitBudget")
          }
          run.budgetTimer = timer
          DispatchQueue.main.asyncAfter(deadline: .now() + Double(remaining) / 1000, execute: timer)
        }
      }
      return
    }
    let skip: String?
    if !isAllowed() {
      skip = "disabled"
    } else if active != nil || waiting != nil {
      skip = "busy"
    } else if isForeground || UIApplication.shared.applicationState != .background {
      skip = "foreground"
    } else {
      skip = nil
    }
    if let skip {
      trace.event("task.skipped", detail: "reason=\(skip)")
      report(identifier: task.identifier, outcome: "skipped", reason: skip)
      task.setTaskCompleted(success: true)
      trace.event("task.completed", detail: "success=true")
      return
    }
    let run = Run(task: task, configuration: policy, trace: trace)
    start(run)
  }

  private func observeExpiration(_ run: Run) {
    let trace = run.trace
    run.task.expirationHandler = { [weak run] in
      trace.event("task.expiration.received")
      DispatchQueue.main.async {
        guard let run else { return }
        trace.event("task.expiration.handled")
        if self.waiting === run {
          self.finishWaiting(run, outcome: "stopped", reason: "expired", success: false)
        } else if self.active === run {
          self.stop(run, reason: "system")
          self.retire(run, outcome: "stopped", reason: "expired", success: false)
        }
      }
    }
  }

  private func start(_ run: Run) {
    run.trace.event(
      "task.start", detail: "applicationState=\(UIApplication.shared.applicationState.rawValue)")
    let policy = run.configuration
    active = run
    observeExpiration(run)
    if let budget = policy.runBudgetMs {
      let timer = DispatchWorkItem { [weak run] in
        guard let run, self.active === run else { return }
        self.stop(run, reason: "budget")
      }
      run.budgetTimer = timer
      DispatchQueue.main.asyncAfter(
        deadline: .now() + Double(max(0, budget - elapsed(run))) / 1000, execute: timer)
    }
    let callback = run.trace.measure("task.callbackLookup") {
      FlutterCallbackCache.lookupCallbackInformation(policy.callbackHandle)
    }
    guard let callback,
      let registrant
    else {
      retire(
        run, outcome: "failed", reason: "bootstrap", error: "Background dispatcher is unavailable")
      return
    }
    let engine = run.trace.measure("task.engine.create") {
      FlutterEngine(
        name: "ente-background-\(run.invocation)", project: nil, allowHeadlessExecution: true)
    }
    run.engine = engine
    let engineStarted = run.trace.measure("task.engine.run") {
      engine.run(withEntrypoint: callback.callbackName, libraryURI: callback.callbackLibraryPath)
    }
    guard engineStarted else {
      retire(run, outcome: "failed", reason: "bootstrap", error: "Flutter engine failed to start")
      return
    }
    let channel = FlutterMethodChannel(
      name: "io.ente.background/worker", binaryMessenger: engine.binaryMessenger)
    run.channel = channel
    channel.setMethodCallHandler { [weak run] call, result in
      guard let run, self.active === run, !run.retiring else {
        result(nil)
        return
      }
      switch call.method {
      case "ready":
        guard !run.ready else {
          result(
            FlutterError(code: "bootstrap", message: "Dispatcher already started", details: nil))
          return
        }
        run.trace.event("task.dart.ready")
        run.ready = true
        var data: [String: Any] = [
          "identifier": policy.identifier,
          "invocation": run.invocation,
          "elapsedMs": self.elapsed(run),
        ]
        if let budget = policy.runBudgetMs { data["runBudgetMs"] = budget }
        if let reason = run.stopReason { data["stopReason"] = reason }
        result(data)
      case "complete":
        guard let data = call.arguments as? [String: Any],
          data["invocation"] as? String == run.invocation,
          let outcome = data["outcome"] as? String,
          ["completed", "skipped", "stopped", "failed"].contains(outcome)
        else {
          result(
            FlutterError(code: "completion", message: "Invalid background completion", details: nil)
          )
          return
        }
        run.trace.event("task.dart.complete", detail: "outcome=\(outcome)")
        result(nil)
        self.retire(run, outcome: outcome, reason: run.stopReason, error: data["error"] as? String)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    run.trace.measure("task.plugins") {
      registrant(engine)
    }
  }

  private func finishWaiting(
    _ run: Run, outcome: String, reason: String, success: Bool = true
  ) {
    guard waiting === run else { return }
    waiting = nil
    run.retiring = true
    run.budgetTimer?.cancel()
    run.task.expirationHandler = nil
    run.task.setTaskCompleted(success: success)
    run.trace.event(
      "task.completed", detail: "outcome=\(outcome) reason=\(reason) success=\(success)")
    report(identifier: run.configuration.identifier, outcome: outcome, reason: reason)
  }

  private func startWaiting() {
    guard active == nil, let run = waiting else { return }
    let reason: String?
    if !configuration.enabled || !isAllowed()
      || !configuration.tasks.contains(where: { $0.identifier == run.configuration.identifier })
    {
      reason = "disabled"
    } else if isForeground || UIApplication.shared.applicationState != .background {
      reason = "foreground"
    } else if let budget = run.configuration.runBudgetMs, elapsed(run) >= budget {
      reason = "waitBudget"
    } else {
      reason = nil
    }
    if let reason {
      finishWaiting(run, outcome: "skipped", reason: reason)
      return
    }
    waiting = nil
    run.budgetTimer?.cancel()
    run.budgetTimer = nil
    Self.logger.info(
      "\(run.configuration.identifier, privacy: .public): refresh finished after \(self.elapsed(run))ms waiting"
    )
    start(run)
  }

  private func elapsed(_ run: Run) -> Int64 {
    Int64(max(0, ProcessInfo.processInfo.systemUptime - run.startedAt) * 1000)
  }

  private func stop(_ run: Run, reason: String) {
    guard active === run, !run.retiring else { return }
    if run.stopReason == nil {
      run.stopReason = reason
      run.trace.event("task.stop", detail: "reason=\(reason) dartReady=\(run.ready)")
      if run.ready {
        run.channel?.invokeMethod(
          "stop", arguments: ["invocation": run.invocation, "reason": reason])
      }
    }
    if reason == "foreground", run.foregroundTimer == nil,
      let grace = run.configuration.foregroundStopTimeoutMs
    {
      let timer = DispatchWorkItem { [weak run] in
        guard let run, self.active === run else { return }
        self.retire(run, outcome: "forcedTeardown", reason: "foreground")
      }
      run.foregroundTimer = timer
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(grace) / 1000, execute: timer)
    }
  }

  private func retire(
    _ run: Run, outcome: String, reason: String? = nil, error: String? = nil, success: Bool? = nil
  ) {
    guard active === run, !run.retiring else { return }
    run.retiring = true
    run.budgetTimer?.cancel()
    run.foregroundTimer?.cancel()
    run.task.expirationHandler = nil
    let terminal = outcome == "completed" && run.stopReason != nil ? "stopped" : outcome
    run.trace.event("task.retire", detail: "outcome=\(terminal) reason=\(reason ?? "none")")
    run.channel?.setMethodCallHandler(nil)
    run.trace.measure("task.engine.destroy") {
      run.engine?.destroyContext()
    }
    run.channel = nil
    run.engine = nil
    let completedSuccessfully = success ?? (terminal != "failed" && terminal != "forcedTeardown")
    run.task.setTaskCompleted(success: completedSuccessfully)
    run.trace.event("task.completed", detail: "success=\(completedSuccessfully)")
    active = nil
    startWaiting()
    if terminal != "completed" {
      report(
        identifier: run.configuration.identifier, outcome: terminal, reason: reason, error: error)
    }
    for result in run.stopResults { result(nil) }
    run.stopResults.removeAll()
  }

  private func report(
    identifier: String, outcome: String, reason: String? = nil, error: String? = nil
  ) {
    var event: [String: Any] = ["identifier": identifier, "outcome": outcome]
    if let reason { event["reason"] = reason }
    if let error { event["error"] = error }
    let fallback = {
      Self.logger.warning(
        "\(identifier, privacy: .public): \(outcome, privacy: .public) (\(reason ?? "task", privacy: .public)) \(error ?? "", privacy: .public)"
      )
    }
    if let observer = observers.allObjects.last(where: \.canReport) {
      observer.report(event, fallback: fallback)
    } else {
      fallback()
    }
  }
}
