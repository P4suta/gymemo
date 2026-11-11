import XCTest

final class WatchTests: XCTestCase {
  @MainActor
  func testLogsASetWithLargerText() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-gymemo-watch-checks", "-gymemo-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
    ]
    app.launch()
    let exercise = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "watch-exercise-")
    ).firstMatch
    XCTAssertTrue(exercise.waitForExistence(timeout: 10))
    exercise.tap()
    let weight = app.descendants(matching: .any)["watch-weight"].firstMatch
    XCTAssertTrue(weight.waitForExistence(timeout: 5))
    let regularHeight = weight.frame.height
    app.terminate()
    app.launchArguments += [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    XCTAssertTrue(exercise.waitForExistence(timeout: 10))
    exercise.tap()
    XCTAssertTrue(weight.waitForExistence(timeout: 5))
    XCTAssertGreaterThan(weight.frame.height, regularHeight)
    let log = app.buttons["watch-log-set"]
    var swipes = 0
    while !log.isHittable && swipes < 15 {
      app.swipeUp()
      swipes += 1
    }
    XCTAssertTrue(log.isHittable)
    log.tap()
    XCTAssertTrue(app.descendants(matching: .any)["watch-pending"].waitForExistence(timeout: 5))
    capture("watch-larger-text")
  }

  @MainActor
  func testExposesStepperValuesAndThePrivacyPolicy() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-gymemo-watch-checks", "-gymemo-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
    ]
    app.launch()
    let first = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "watch-exercise-")
    ).firstMatch
    XCTAssertTrue(first.waitForExistence(timeout: 10))
    first.tap()
    let weight = app.descendants(matching: .any)["watch-weight"].firstMatch
    XCTAssertTrue(weight.waitForExistence(timeout: 5))
    XCTAssertEqual(weight.value as? String, "Bodyweight")
    capture("watch-entry")
    let reps = app.descendants(matching: .any)["watch-reps"].firstMatch
    var swipes = 0
    while !reps.exists && swipes < 8 {
      app.swipeUp()
      swipes += 1
    }
    XCTAssertTrue(reps.exists)
    XCTAssertEqual(reps.value as? String, "1 rep")
    app.terminate()
    app.launch()
    readPrivacy(in: app)
  }

  @MainActor
  func testReadsEveryPrivacyFactWithLargerText() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-gymemo-watch-checks", "-gymemo-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    readPrivacy(in: app)
  }

  @MainActor
  private func readPrivacy(in app: XCUIApplication) {
    let privacy = app.buttons["watch-privacy"]
    var swipes = 0
    while !privacy.isHittable && swipes < 15 {
      app.swipeUp()
      swipes += 1
    }
    XCTAssertTrue(privacy.exists)
    privacy.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["privacy-collection"].waitForExistence(timeout: 5))
    capture("watch-privacy")
    let facts = [
      "privacy-collection", "privacy-retention", "privacy-watch", "privacy-sync",
      "privacy-backup", "privacy-files", "privacy-deletion", "privacy-erase-devices",
      "privacy-delete-copies",
    ]
    var unread = Set(facts)
    var rotationsWithoutReading = 0
    while rotationsWithoutReading < 20 {
      let reached = unread.filter { identifier in
        let text = app.descendants(matching: .any)[identifier]
        return text.exists && text.isHittable && !text.label.isEmpty
      }
      if !reached.isEmpty {
        unread.subtract(reached)
        rotationsWithoutReading = 0
      }
      if unread.isEmpty { break }
      guard let identifier = facts.first(where: unread.contains) else { break }
      let next = app.descendants(matching: .any)[identifier]
      let direction = next.exists && next.frame.maxY < app.frame.minY ? -1.0 : 1.0
      // https://developer.apple.com/documentation/xcuiautomation/xcuidevice
      XCUIDevice.shared.rotateDigitalCrown(delta: direction * 0.125)
      rotationsWithoutReading += 1
    }
    if !unread.isEmpty {
      let tree = XCTAttachment(string: app.debugDescription)
      tree.name = "watch-privacy-hierarchy"
      tree.lifetime = .keepAlways
      add(tree)
    }
    XCTAssertTrue(unread.isEmpty, "Privacy facts were not accessible: \(unread.sorted())")
    capture("watch-privacy-end")
  }

  @MainActor
  func testKeepsAnUnacknowledgedSetAfterRelaunch() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-gymemo-watch-checks", "-gymemo-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
    ]
    app.launch()
    let first = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "watch-exercise-")
    ).firstMatch
    XCTAssertTrue(first.waitForExistence(timeout: 10))
    first.tap()
    let log = app.buttons["watch-log-set"]
    var swipes = 0
    while !log.isHittable && swipes < 5 {
      app.swipeUp()
      swipes += 1
    }
    XCTAssertTrue(log.exists)
    log.tap()
    XCTAssertTrue(app.descendants(matching: .any)["watch-pending"].waitForExistence(timeout: 5))
    capture("watch-pending")
    app.terminate()
    app.launchArguments.removeAll { $0 == "-gymemo-reset" }
    app.launch()
    let delivery = app.buttons["watch-delivery"]
    swipes = 0
    while !delivery.isHittable && swipes < 15 {
      app.swipeUp()
      swipes += 1
    }
    XCTAssertTrue(delivery.exists)
    delivery.tap()
    XCTAssertTrue(app.descendants(matching: .any)["watch-pending"].waitForExistence(timeout: 5))
    capture("watch-relaunched")
  }

  @MainActor
  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
