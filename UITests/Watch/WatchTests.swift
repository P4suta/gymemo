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
    let privacy = app.buttons["watch-privacy"]
    swipes = 0
    while !privacy.isHittable && swipes < 15 {
      app.swipeUp()
      swipes += 1
    }
    XCTAssertTrue(privacy.exists)
    privacy.tap()
    XCTAssertTrue(app.staticTexts["privacy-collection"].waitForExistence(timeout: 5))
    capture("watch-privacy")
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
