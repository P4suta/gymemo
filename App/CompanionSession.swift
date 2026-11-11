#if os(iOS) || os(watchOS)
  import Foundation
  import GymemoCore
  import GymemoKit
  import Synchronization
  import WatchConnectivity

  enum CompanionTransferFailure: Equatable, Sendable {
    case payload(CompanionFailure)
    case system(Int)
  }

  /// All app and store callbacks run on the main actor, outside the session's delegate queue.
  @MainActor
  final class CompanionSession: NSObject, WCSessionDelegate {
    var onMessage: ((CompanionMessage) -> Void)?
    var onActivation: (() -> Void)?
    var onDrain: (() -> Void)?
    var onFailure: ((CompanionTransferFailure) -> Void)?
    private let session = WCSession.default
    private nonisolated let pendingCallbacks = Mutex(0)
    private var activationFinished = false
    private var backgroundWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var pendingObservation: NSKeyValueObservation?
    private var activationObservation: NSKeyValueObservation?

    static var isSupported: Bool { WCSession.isSupported() }

    func start() {
      guard Self.isSupported else { return }
      session.delegate = self
      pendingObservation = session.observe(\.hasContentPending) { [weak self] _, _ in
        Task { @MainActor in self?.completeBackgroundWaiters() }
      }
      activationObservation = session.observe(\.activationState) { [weak self] _, _ in
        Task { @MainActor in self?.completeBackgroundWaiters() }
      }
      session.activate()
    }

    func finishBackgroundDelivery() async {
      let id = UUID()
      await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          if Task.isCancelled {
            continuation.resume()
          } else {
            backgroundWaiters[id] = continuation
            completeBackgroundWaiters()
          }
        }
      } onCancel: {
        Task { @MainActor [weak self] in
          self?.backgroundWaiters.removeValue(forKey: id)?.resume()
        }
      }
    }

    private func completeBackgroundWaiters() {
      guard activationFinished,
        session.activationState != .activated || !session.hasContentPending,
        pendingCallbacks.withLock({ $0 == 0 })
      else { return }
      let waiting = backgroundWaiters.values
      backgroundWaiters.removeAll()
      for continuation in waiting { continuation.resume() }
    }

    private nonisolated func enqueue(_ data: Data) {
      pendingCallbacks.withLock { $0 += 1 }
      Task { @MainActor [weak self] in
        guard let self else { return }
        receive(data)
        pendingCallbacks.withLock { $0 -= 1 }
        completeBackgroundWaiters()
      }
    }

    @discardableResult
    func send(_ message: CompanionMessage) -> Bool {
      guard canTransfer else { return false }
      do {
        let data = try CompanionCodec.encode(message)
        if !session.outstandingUserInfoTransfers.contains(where: {
          ($0.userInfo["gymemo"] as? Data) == data
        }) {
          session.transferUserInfo(["gymemo": data])
        }
        return true
      } catch {
        onFailure?(.payload(error))
        return false
      }
    }

    func publish(_ catalog: CompanionCatalog) {
      guard canTransfer else { return }
      do {
        let data = try CompanionCodec.encode(.catalog(catalog))
        if (session.applicationContext["gymemo"] as? Data) != data {
          try session.updateApplicationContext(["gymemo": data])
        }
      } catch let failure as CompanionFailure {
        onFailure?(.payload(failure))
      } catch {
        onFailure?(.system((error as NSError).code))
      }
    }

    private var canTransfer: Bool {
      guard session.activationState == .activated else { return false }
      #if os(iOS)
        return session.isPaired && session.isWatchAppInstalled
      #else
        return session.isCompanionAppInstalled
      #endif
    }

    private func receive(_ data: Data) {
      do { onMessage?(try CompanionCodec.decode(data)) } catch {
        onFailure?(.payload(error))
      }
    }

    nonisolated func session(
      _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
      error: (any Error)?
    ) {
      let code = error.map { ($0 as NSError).code }
      let activated = activationState == .activated
      Task { @MainActor [weak self] in
        guard let self else { return }
        activationFinished = true
        if let code { onFailure?(.system(code)) }
        guard activated else {
          completeBackgroundWaiters()
          return
        }
        if let data = self.session.receivedApplicationContext["gymemo"] as? Data {
          receive(data)
        }
        onActivation?()
        completeBackgroundWaiters()
      }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
      guard let data = userInfo["gymemo"] as? Data else { return }
      enqueue(data)
    }

    nonisolated func session(
      _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
    ) {
      guard let data = applicationContext["gymemo"] as? Data else { return }
      enqueue(data)
    }

    nonisolated func session(
      _ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer,
      error: (any Error)?
    ) {
      let code = error.map { ($0 as NSError).code }
      Task { @MainActor [weak self] in
        if let code { self?.onFailure?(.system(code)) } else { self?.onDrain?() }
      }
    }

    #if os(iOS)
      nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

      nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.session.activate() }
      }

      nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.onActivation?() }
      }
    #endif
  }
#endif
