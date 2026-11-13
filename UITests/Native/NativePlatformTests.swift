import AppIntentsTesting
import XCTest

#if os(macOS)
  import AppKit
#endif

final class NativePlatformTests: XCTestCase {
  @MainActor
  func testOpensSettingsDestinationsFromTheirRows() {
    let app = launch("settings-rows", tab: "settings")
    let backup = app.buttons["open-backup"].firstMatch
    XCTAssertTrue(backup.waitForExistence(timeout: 10))
    for identifier in ["open-exercises", "open-privacy"] {
      let row = app.buttons[identifier].firstMatch
      XCTAssertEqual(row.frame.minX, backup.frame.minX, accuracy: 1)
      XCTAssertEqual(row.frame.maxX, backup.frame.maxX, accuracy: 1)
      XCTAssertFalse(row.label.isEmpty)
    }
    keepScreenshot("native-settings", anchoredBy: "open-backup")
    let tree = XCTAttachment(string: app.debugDescription)
    tree.name = "native-settings-accessibility"
    tree.lifetime = .keepAlways
    add(tree)
    let storage = app.staticTexts["storage-text"].firstMatch
    let explanation = "Records stay on each device."
    XCTAssertTrue(storage.label == explanation || storage.value as? String == explanation)
    activate(backup)
    XCTAssertTrue(app.buttons["import-backup"].firstMatch.waitForExistence(timeout: 5))
    #if os(macOS)
      activate(app.buttons["chevron.backward"].firstMatch)
    #else
      activate(app.buttons["BackButton"].firstMatch)
    #endif
    let exercises = app.buttons["open-exercises"].firstMatch
    XCTAssertTrue(exercises.waitForExistence(timeout: 5))
    activate(exercises)
    XCTAssertTrue(app.buttons["create-exercise"].firstMatch.waitForExistence(timeout: 5))
  }

  @available(iOS 27.2, macOS 27.2, visionOS 27.2, *)
  @MainActor
  func testOpensTheLogThroughTheAppIntentsInfrastructure() async throws {
    let app = launch("shortcut-log", tab: "analysis")
    XCTAssertTrue(app.staticTexts["weekly-headline"].waitForExistence(timeout: 10))
    #if os(macOS)
      let windowCount = app.windows.count
    #endif
    let definitions = IntentDefinitions(bundleIdentifier: "com.p4suta.gymemo")
    _ = try await definitions.intents["OpenLogIntent"].makeIntent().run()
    XCTAssertTrue(app.buttons["log-set-Bench Press"].firstMatch.waitForExistence(timeout: 5))
    #if os(macOS)
      XCTAssertEqual(app.windows.count, windowCount)
    #endif
  }

  @MainActor
  func testReadsEveryPrivacyFact() throws {
    let app = launch("privacy", tab: "settings")
    let privacy = app.buttons["open-privacy"].firstMatch
    XCTAssertTrue(privacy.waitForExistence(timeout: 10))
    bringIntoView(privacy, in: app)
    activate(privacy)
    let collection = app.descendants(matching: .any)["privacy-collection"].firstMatch
    XCTAssertTrue(collection.waitForExistence(timeout: 5))
    keepScreenshot("native-privacy", anchoredBy: "privacy-collection")
    for identifier in [
      "privacy-collection", "privacy-retention", "privacy-watch", "privacy-sync",
      "privacy-backup", "privacy-files", "privacy-deletion", "privacy-erase-devices",
      "privacy-delete-copies",
    ] {
      let fact = app.descendants(matching: .any)[identifier].firstMatch
      bringIntoView(fact, in: app)
      XCTAssertTrue(fact.isHittable, "\(identifier) must be reachable")
      XCTAssertFalse(
        fact.label.isEmpty && (fact.value as? String ?? "").isEmpty,
        "\(identifier) must expose readable text")
    }
    #if os(iOS) || os(visionOS)
      try audit(app)
    #endif
  }

  @MainActor
  private func launch(
    _ name: String, tab: String, language: String = "en", assistive: Bool = false
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-gymemo-store", "native-\(name)", "-gymemo-reset", "-gymemo-sample", "-gymemo-today",
      "2026-11-09", "-gymemo-tab", tab, "-AppleLanguages", "(\(language))", "-AppleLocale",
      language == "ja" ? "ja_JP" : "en_US",
    ]
    if assistive { app.launchArguments.append("-gymemo-assistive") }
    launch(app)
    #if os(macOS)
      for remaining in stride(from: app.windows.count - 1, through: 1, by: -1) {
        app.windows.element(boundBy: remaining).buttons[XCUIIdentifierCloseWindow].click()
        let closed = expectation(
          for: NSPredicate(format: "count == %d", remaining), evaluatedWith: app.windows)
        wait(for: [closed], timeout: 5)
      }
      XCTAssertEqual(app.windows.count, 1)
    #endif
    return app
  }

  @MainActor
  private func launch(_ app: XCUIApplication) {
    app.launch()
    #if os(macOS)
      app.activate()
      let window = app.windows.firstMatch
      XCTAssertTrue(window.waitForExistence(timeout: 10))
      app.typeKey("c", modifierFlags: [.control, .function])
      guard let screen = NSScreen.screens.first else {
        XCTFail("The Mac test requires a primary display")
        return
      }
      let bounds = CGRect(origin: .zero, size: screen.frame.size)
      XCTAssertTrue(
        bounds.contains(window.frame),
        "The Mac test window \(window.frame) must fit inside the primary display \(bounds)")
    #endif
  }

  @MainActor
  func testOpensOnlyTheParameterlessLogLink() throws {
    let app = launch("log-link", tab: "analysis")
    XCTAssertTrue(app.staticTexts["weekly-headline"].waitForExistence(timeout: 10))
    app.terminate()
    app.open(try XCTUnwrap(URL(string: "com.p4suta.gymemo://log?delete=all")))
    XCTAssertTrue(app.staticTexts["weekly-headline"].waitForExistence(timeout: 5))
    app.terminate()
    app.open(try XCTUnwrap(URL(string: "com.p4suta.gymemo://log")))
    defer { app.terminate() }
    XCTAssertTrue(app.buttons["log-set-Bench Press"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["set-1-Bench Press"].firstMatch.exists)
  }

  @MainActor
  func testSelectsAHistoryDayAndReturnsToItsList() throws {
    let app = launch("history", tab: "history")
    let day = app.buttons["day-2026-11-06"].firstMatch
    XCTAssertTrue(day.waitForExistence(timeout: 10))
    activate(day)
    XCTAssertTrue(app.buttons["log-set-Deadlift"].firstMatch.waitForExistence(timeout: 5))
    if !day.exists {
      activate(app.buttons["BackButton"].firstMatch)
      XCTAssertTrue(day.waitForExistence(timeout: 5))
      activate(day)
      XCTAssertTrue(app.buttons["log-set-Deadlift"].firstMatch.waitForExistence(timeout: 5))
    }
    keepScreenshot("native-history", anchoredBy: "log-set-Deadlift")
    #if os(iOS) || os(visionOS)
      try audit(app)
    #endif
  }

  @MainActor
  func testSelectsAnExerciseAndChangesTheProgressRange() throws {
    let app = launch("analysis", tab: "analysis")
    let bench = app.buttons["progress-Bench Press"].firstMatch
    XCTAssertTrue(bench.waitForExistence(timeout: 10))
    activate(bench)
    XCTAssertTrue(app.staticTexts["best-score"].firstMatch.waitForExistence(timeout: 5))
    if !bench.exists {
      activate(app.buttons["BackButton"].firstMatch)
      XCTAssertTrue(bench.waitForExistence(timeout: 5))
      activate(bench)
      XCTAssertTrue(app.staticTexts["best-score"].firstMatch.waitForExistence(timeout: 5))
    }
    let range = app.descendants(matching: .any).matching(identifier: "All").firstMatch
    XCTAssertTrue(range.waitForExistence(timeout: 5))
    activate(range)
    let selected = expectation(
      for: NSPredicate(
        format: "selected == true OR value == %@ OR value == %@", "1", NSNumber(value: 1)),
      evaluatedWith: range)
    wait(for: [selected], timeout: 5)
    #if os(iOS) || os(visionOS)
      let chart = app.descendants(matching: .any)["progress-chart"].firstMatch
      let first = chart.descendants(matching: .any).matching(
        NSPredicate(format: "label == %@", "Mon, Sep 21, 2026")
      ).firstMatch
      let last = chart.descendants(matching: .any).matching(
        NSPredicate(format: "label == %@", "Mon, Nov 9, 2026")
      ).firstMatch
      XCTAssertEqual(first.value as? String, "69.7 kg")
      XCTAssertEqual(last.value as? String, "80.8 kg")
    #endif
    keepScreenshot("native-analysis", anchoredBy: "best-score")
    let tree = XCTAttachment(string: app.debugDescription)
    tree.name = "native-analysis-accessibility"
    tree.lifetime = .keepAlways
    add(tree)
    #if os(iOS) || os(visionOS)
      try audit(app)
    #endif
  }

  @MainActor
  func testLogsAndRestoresASetInJapanese() {
    let app = launch("japanese-log", tab: "log", language: "ja")
    let log = app.buttons["log-set-ベンチプレス"].firstMatch
    bringIntoView(log, in: app)
    XCTAssertTrue(log.exists)
    activate(log)
    let added = app.buttons["set-4-ベンチプレス"].firstMatch
    XCTAssertTrue(added.waitForExistence(timeout: 5))
    keepScreenshot("native-japanese-log", anchoredBy: "set-4-ベンチプレス")
    app.terminate()
    app.launchArguments.removeAll { $0 == "-gymemo-reset" || $0 == "-gymemo-sample" }
    launch(app)
    bringIntoView(added, in: app)
    XCTAssertTrue(added.exists)
  }

  #if os(iOS)
    @available(iOS 27.2, *)
    @MainActor
    func testKeepsGuidedInputWhenOpeningTheLogShortcut() async throws {
      let app = launch("assistive-shortcut", tab: "log", assistive: true)
      let start = app.buttons["assistive-start"]
      XCTAssertTrue(start.waitForExistence(timeout: 10))
      start.tap()
      app.buttons["assistive-exercise-Bench Press"].tap()
      let weight = app.textFields["assistive-weight"]
      replaceText(weight, with: "80", in: app)
      let definitions = IntentDefinitions(bundleIdentifier: "com.p4suta.gymemo")
      _ = try await definitions.intents["OpenLogIntent"].makeIntent().run()
      XCTAssertEqual(weight.value as? String, "80")
      app.buttons["assistive-next"].tap()
      XCTAssertTrue(app.textFields["assistive-reps"].waitForExistence(timeout: 5))
    }

    #if !targetEnvironment(simulator)
      @MainActor
      func testOpensTheLogThroughSiri() {
        let app = launch("siri-log", tab: "analysis")
        XCTAssertTrue(app.staticTexts["weekly-headline"].waitForExistence(timeout: 10))
        XCUIDevice.shared.siriService.activate(voiceRecognitionText: "Open the log in gymemo")
        let tree = XCTAttachment(string: XCUIDevice.shared.siriService.debugDescription)
        tree.name = "siri-log"
        tree.lifetime = .keepAlways
        add(tree)
        XCTAssertTrue(app.buttons["log-set-Bench Press"].firstMatch.waitForExistence(timeout: 15))
      }
    #endif

    @MainActor
    func testKeepsUncommittedInputWhenTheAvailableSpaceChanges() {
      let app = launch("resize-input", tab: "log")
      let weight = app.textFields["weight-Bench Press"].firstMatch
      let reps = app.textFields["reps-Bench Press"].firstMatch
      bringIntoView(weight, in: app)
      replaceText(weight, with: "80", in: app)
      replaceText(reps, with: "7", in: app)
      let keyboard = app.buttons["hide-keyboard"].firstMatch
      if keyboard.exists { keyboard.tap() }
      XCUIDevice.shared.orientation = .landscapeLeft
      defer { XCUIDevice.shared.orientation = .portrait }
      bringIntoView(weight, in: app)
      XCTAssertEqual(weight.value as? String, "80")
      XCTAssertEqual(reps.value as? String, "7")
      keepScreenshot("native-resized-input", anchoredBy: "weight-Bench Press")
      XCUIDevice.shared.orientation = .portrait
      bringIntoView(weight, in: app)
      XCTAssertEqual(weight.value as? String, "80")
      XCTAssertEqual(reps.value as? String, "7")
    }

    @MainActor
    private func replaceText(_ element: XCUIElement, with text: String, in app: XCUIApplication) {
      let keyboard = app.buttons["hide-keyboard"].firstMatch
      if keyboard.exists { keyboard.tap() }
      bringIntoView(element, in: app)
      element.tap()
      let clear = app.buttons["clear-\(element.identifier)"].firstMatch
      XCTAssertTrue(clear.waitForExistence(timeout: 3))
      clear.tap()
      app.typeText(text)
      if keyboard.exists { keyboard.tap() }
    }
  #endif

  #if os(macOS)
    @MainActor
    func testKeepsAnUncommittedSetWhenSwitchingAreas() {
      let app = launch("draft", tab: "log")
      let weight = app.textFields["weight-Bench Press"].firstMatch
      let reps = app.textFields["reps-Bench Press"].firstMatch
      XCTAssertTrue(weight.waitForExistence(timeout: 10))
      app.activate()
      replaceText(weight, with: "80")
      replaceText(reps, with: "7")
      app.typeKey("3", modifierFlags: .command)
      XCTAssertTrue(app.staticTexts["weekly-headline"].waitForExistence(timeout: 5))
      app.typeKey("1", modifierFlags: .command)
      XCTAssertTrue(weight.waitForExistence(timeout: 5))
      XCTAssertEqual(weight.value as? String, "80")
      XCTAssertEqual(reps.value as? String, "7")
      replaceText(reps, with: "0")
      app.buttons["log-set-Bench Press"].firstMatch.click()
      let problem = app.descendants(matching: .any)["problem-Bench Press"].firstMatch
      XCTAssertTrue(problem.waitForExistence(timeout: 5))
      XCTAssertFalse(app.buttons["set-4-Bench Press"].firstMatch.exists)
      app.typeKey("3", modifierFlags: .command)
      XCTAssertTrue(app.staticTexts["weekly-headline"].waitForExistence(timeout: 5))
      app.typeKey("1", modifierFlags: .command)
      XCTAssertTrue(problem.waitForExistence(timeout: 5))
      XCTAssertEqual(reps.value as? String, "0")
      replaceText(reps, with: "7")
      app.buttons["log-set-Bench Press"].firstMatch.click()
      XCTAssertTrue(app.buttons["set-4-Bench Press"].firstMatch.waitForExistence(timeout: 5))
      XCTAssertFalse(problem.exists)
    }

    @MainActor
    func testKeepsSeparateUncommittedSetsForEachDay() {
      let app = launch("day-drafts", tab: "log")
      let weight = app.textFields["weight-Bench Press"].firstMatch
      let reps = app.textFields["reps-Bench Press"].firstMatch
      XCTAssertTrue(weight.waitForExistence(timeout: 10))
      app.activate()
      replaceText(weight, with: "80")
      replaceText(reps, with: "7")
      app.typeKey("2", modifierFlags: .command)
      let day = app.buttons["day-2026-11-02"].firstMatch
      XCTAssertTrue(day.waitForExistence(timeout: 5))
      day.click()
      XCTAssertTrue(weight.waitForExistence(timeout: 5))
      XCTAssertEqual(weight.value as? String, "62.5")
      replaceText(weight, with: "70")
      replaceText(reps, with: "9")
      app.typeKey("1", modifierFlags: .command)
      XCTAssertTrue(weight.waitForExistence(timeout: 5))
      XCTAssertEqual(weight.value as? String, "80")
      XCTAssertEqual(reps.value as? String, "7")
      app.typeKey("2", modifierFlags: .command)
      XCTAssertTrue(weight.waitForExistence(timeout: 5))
      XCTAssertEqual(weight.value as? String, "70")
      XCTAssertEqual(reps.value as? String, "9")
    }

    @MainActor
    func testKeepsUncommittedSetsIndependentBetweenWindows() throws {
      let app = launch("window-drafts", tab: "log")
      XCTAssertTrue(app.textFields["weight-Bench Press"].firstMatch.waitForExistence(timeout: 10))
      let original = try XCTUnwrap(app.windows.allElementsBoundByAccessibilityElement.first)
      let count = app.windows.count
      let weight = original.textFields["weight-Bench Press"].firstMatch
      let reps = original.textFields["reps-Bench Press"].firstMatch
      XCTAssertTrue(weight.waitForExistence(timeout: 10))
      app.activate()
      replaceText(weight, with: "80")
      replaceText(reps, with: "7")
      app.typeKey("n", modifierFlags: .command)
      let secondWindow = expectation(
        for: NSPredicate(format: "count == %d", count + 1), evaluatedWith: app.windows)
      wait(for: [secondWindow], timeout: 5)
      let second = try XCTUnwrap(
        app.windows.allElementsBoundByAccessibilityElement.first { window in
          window.textFields["weight-Bench Press"].firstMatch.value as? String == "63.75"
        })
      let secondWeight = second.textFields["weight-Bench Press"].firstMatch
      let secondReps = second.textFields["reps-Bench Press"].firstMatch
      XCTAssertEqual(secondReps.value as? String, "6")
      replaceText(secondWeight, with: "90")
      replaceText(secondReps, with: "8")
      XCTAssertEqual(weight.value as? String, "80")
      XCTAssertEqual(reps.value as? String, "7")
      XCTAssertEqual(secondWeight.value as? String, "90")
      XCTAssertEqual(secondReps.value as? String, "8")
      app.typeKey("w", modifierFlags: .command)
    }

    @MainActor
    private func replaceText(_ element: XCUIElement, with text: String) {
      element.coordinate(withNormalizedOffset: .init(dx: 0.99, dy: 0.5)).click()
      element.typeKey("a", modifierFlags: .command)
      element.typeText(text)
      XCTAssertEqual(element.value as? String, text)
    }

    @MainActor
    func testKeepsSelectionsWhenSwitchingAreas() {
      let app = launch("selections", tab: "history")
      let day = app.buttons["day-2026-11-06"].firstMatch
      XCTAssertTrue(day.waitForExistence(timeout: 10))
      day.click()
      XCTAssertTrue(app.buttons["log-set-Deadlift"].firstMatch.waitForExistence(timeout: 5))
      XCTAssertEqual(app.splitGroups.count, 1)
      app.typeKey("3", modifierFlags: .command)
      let exercise = app.buttons["progress-Bench Press"].firstMatch
      XCTAssertTrue(exercise.waitForExistence(timeout: 5))
      exercise.click()
      XCTAssertTrue(app.staticTexts["best-score"].firstMatch.waitForExistence(timeout: 5))
      XCTAssertEqual(app.splitGroups.count, 1)
      app.typeKey("2", modifierFlags: .command)
      XCTAssertTrue(app.buttons["log-set-Deadlift"].firstMatch.waitForExistence(timeout: 5))
      app.typeKey("3", modifierFlags: .command)
      XCTAssertTrue(app.staticTexts["best-score"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testConfirmsASetWithReturnAndClosesTheEditorWithEscape() {
      let app = launch("editor-keys", tab: "log")
      let set = app.buttons["set-1-Bench Press"].firstMatch
      XCTAssertTrue(set.waitForExistence(timeout: 10))
      set.click()
      let reps = app.textFields["edit-reps"]
      XCTAssertTrue(reps.waitForExistence(timeout: 5))
      reps.click()
      reps.typeKey("a", modifierFlags: .command)
      reps.typeText("7")
      app.typeKey(.return, modifierFlags: [])
      XCTAssertTrue(reps.waitForNonExistence(timeout: 5))
      XCTAssertTrue(set.label.contains("7 reps"))
      set.click()
      XCTAssertTrue(reps.waitForExistence(timeout: 5))
      app.typeKey(.escape, modifierFlags: [])
      XCTAssertTrue(reps.waitForNonExistence(timeout: 5))
      XCTAssertTrue(set.label.contains("7 reps"))
    }

    @MainActor
    func testUndoesAndRedoesACommittedSetFromTheKeyboard() {
      let app = launch("undo", tab: "log")
      let button = app.buttons["log-set-Bench Press"].firstMatch
      XCTAssertTrue(button.waitForExistence(timeout: 10))
      let added = app.buttons["set-4-Bench Press"].firstMatch
      XCTAssertFalse(added.exists)
      button.click()
      XCTAssertTrue(added.waitForExistence(timeout: 5))
      app.typeKey("z", modifierFlags: .command)
      XCTAssertTrue(added.waitForNonExistence(timeout: 5))
      app.typeKey("z", modifierFlags: [.command, .shift])
      XCTAssertTrue(added.waitForExistence(timeout: 5))
      keepScreenshot("mac-undo", anchoredBy: "set-4-Bench Press")
    }

    @MainActor
    func testNavigatesWithTheStandardCommandShortcuts() {
      let app = launch("commands", tab: "log")
      app.typeKey("2", modifierFlags: .command)
      XCTAssertTrue(app.buttons["day-2026-11-06"].firstMatch.waitForExistence(timeout: 5))
      app.typeKey("3", modifierFlags: .command)
      XCTAssertTrue(app.staticTexts["weekly-headline"].firstMatch.waitForExistence(timeout: 5))
      app.typeKey("4", modifierFlags: .command)
      XCTAssertTrue(app.buttons["open-privacy"].firstMatch.waitForExistence(timeout: 5))
    }
  #endif

  @MainActor
  private func bringIntoView(_ element: XCUIElement, in app: XCUIApplication) {
    var scrolls = 0
    while !element.isHittable && scrolls < 12 {
      #if os(macOS)
        app.scroll(byDeltaX: 0, deltaY: -400)
      #else
        app.swipeUp()
      #endif
      scrolls += 1
    }
  }

  @MainActor
  private func audit(_ app: XCUIApplication) throws {
    #if os(iOS) || os(visionOS)
      try app.performAccessibilityAudit(for: [.elementDetection, .sufficientElementDescription]) {
        issue in
        // Swift Charts draws axis text without separate elements; its marks carry spoken labels and values.
        if issue.auditType == .elementDetection && issue.element == nil
          && app.descendants(matching: .any)["progress-chart"].firstMatch.exists
        {
          return true
        }
        let element = issue.element.map { "\($0.identifier): \($0.label)" } ?? "no element"
        XCTFail("\(issue.compactDescription) on \(element): \(issue.detailedDescription)")
        return true
      }
    #endif
  }

  @MainActor
  private func activate(_ element: XCUIElement) {
    #if os(macOS)
      element.click()
    #else
      element.tap()
    #endif
  }

  @MainActor
  private func keepScreenshot(_ name: String, anchoredBy identifier: String) {
    let window = XCUIApplication().windows.containing(.any, identifier: identifier).firstMatch
    XCTAssertTrue(window.exists)
    let attachment = XCTAttachment(screenshot: window.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    #if os(visionOS)
      let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      screen.name = "\(name)-screen"
      screen.lifetime = .keepAlways
      add(screen)
    #endif
  }
}
