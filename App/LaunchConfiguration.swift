import Foundation
import GymemoCopy
import GymemoCore
import GymemoKit

enum LaunchFailure: Error, Equatable {
  case location
  case store(StoreFailure)
}

enum RootTab: String, CaseIterable, Hashable, Sendable {
  case log
  case history
  case analysis
  case settings
}

/// How one launch finds its store and its clock.
/// A debug build reads launch arguments, so a UI test runs on its own file with a fixed day.
struct LaunchConfiguration: Sendable {
  var storeName: String?
  var resetsStore = false
  var fixedToday: LocalDay?
  var usesSampleLog = false
  var initialTab = RootTab.log
  var usesAssistiveInterface = false

  static let current: LaunchConfiguration = {
    #if DEBUG
      return LaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
    #else
      return LaunchConfiguration()
    #endif
  }()

  init() {}

  #if DEBUG
    init(arguments: [String]) {
      var remaining = arguments.dropFirst().makeIterator()
      while let argument = remaining.next() {
        switch argument {
        case "-gymemo-store":
          storeName = remaining.next().flatMap { name in
            let isPlain = name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
            return isPlain && !name.isEmpty ? name : nil
          }
        case "-gymemo-reset": resetsStore = true
        case "-gymemo-today": fixedToday = remaining.next().flatMap(LocalDay.init(iso:))
        case "-gymemo-sample": usesSampleLog = true
        case "-gymemo-assistive": usesAssistiveInterface = true
        case "-gymemo-tab":
          initialTab = remaining.next().flatMap(RootTab.init(rawValue:)) ?? .log
        default: continue
        }
      }
    }
  #endif

  func currentDay() -> LocalDay {
    fixedToday ?? LocalDay.nearest(to: Date(), in: .current)
  }

  func starter() -> TrainingLog {
    #if DEBUG
      if usesSampleLog { return SampleLog.make(endingOn: currentDay()) }
    #endif
    return TrainingLog.starter(named: copy.starterName)
  }

  func storeURL() throws(LaunchFailure) -> URL {
    let manager = FileManager.default
    if let storeName {
      let url = manager.temporaryDirectory.appending(
        path: "\(storeName).sqlite", directoryHint: .notDirectory)
      if resetsStore {
        for suffix in ["", "-journal"] {
          try? manager.removeItem(at: URL(filePath: url.path + suffix))
        }
      }
      return url
    }
    guard
      let directory = try? manager.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    else { throw .location }
    return directory.appending(path: "gymemo.sqlite", directoryHint: .notDirectory)
  }
}

/// The state of the app after it tried to open its store.
@MainActor
enum Launch {
  case ready(AppModel)
  case failed(LaunchFailure)

  static func start(_ configuration: LaunchConfiguration) -> Launch {
    do {
      let url = try configuration.storeURL()
      let store = try TrainingLogStore(url: url, starter: configuration.starter())
      let log = try store.load()
      return .ready(
        AppModel(
          store: store, log: log, currentDay: configuration.currentDay,
          connectsToWatch: configuration.storeName == nil && !configuration.usesSampleLog
            && configuration.fixedToday == nil))
    } catch let failure as LaunchFailure {
      return .failed(failure)
    } catch let failure as StoreFailure {
      return .failed(.store(failure))
    } catch {
      return .failed(.location)
    }
  }
}
