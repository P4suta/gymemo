import XCTest

final class AssistiveLoggingTests: XCTestCase {
  @MainActor
  func testLogsOneSetThroughTheGuidedStepsAndKeepsItAfterRelaunch() {
    var app = Gymemo.launch(store: "assistive-log", assistive: true)
    app.buttons["assistive-start"].required("the guided start").tap()
    app.buttons["assistive-exercise-Bench Press"].required("the exercise").tap()
    app.fill("assistive-weight", with: "60")
    app.buttons["assistive-next"].tap()
    app.fill("assistive-reps", with: "10")
    app.buttons["assistive-next"].tap()
    XCTAssertTrue(app.staticTexts["assistive-summary"].required("the review").label.contains("60"))
    app.buttons["assistive-confirm"].tap()
    app.staticTexts["assistive-saved"].required("the saved result")
    capture("assistive-saved")
    app.terminate()
    app = Gymemo.launch(store: "assistive-log", reset: false)
    XCTAssertEqual(
      app.buttons["set-1-Bench Press"].required("the saved set").label,
      "Set 1, 60 kilograms, 10 reps")
  }

  @MainActor
  func testGuidedEntryExplainsAnInvalidValueBeforeContinuing() {
    let app = Gymemo.launch(store: "assistive-invalid", assistive: true)
    app.buttons["assistive-start"].required("the guided start").tap()
    app.buttons["assistive-exercise-Bench Press"].required("the exercise").tap()
    app.fill("assistive-weight", with: "1000")
    app.buttons["assistive-next"].tap()
    app.any("assistive-problem").required("the weight problem")
    XCTAssertFalse(app.textFields["assistive-reps"].exists)
    app.fill("assistive-weight", with: "60")
    app.buttons["assistive-next"].tap()
    app.fill("assistive-reps", with: "")
    app.buttons["assistive-next"].tap()
    XCTAssertEqual(
      app.any("assistive-problem").required("the repetitions problem").label, "Enter the reps.")
  }
}
