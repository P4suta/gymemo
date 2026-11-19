import XCTest

@MainActor
final class ActivityLogTests: XCTestCase {
  private let walking = "pick-activity-00000000-0000-0000-0000-000000000001"

  func testLogsAWalkAndKeepsItAfterRelaunch() {
    let app = Gymemo.launch(store: "log-walking")
    app.buttons["add-first-exercise"].required("the add button").tap()
    let choice = app.buttons[walking].required("Walking")
    capture("timed-activity-picker")
    choice.tap()
    app.textFields["activity-duration"].required("the duration field")
    capture("walking-entry")
    app.buttons["sheet-confirm"].required("Save").tap()
    app.any("activity-duration-problem").required("the duration problem")
    app.textFields["activity-duration"].scrollAndTap(in: app)
    app.typeText("20")
    app.hideKeyboard()
    app.buttons["sheet-confirm"].required("Save").tap()
    app.staticTexts["20 min"].required("the recorded duration")
    capture("walking-in-log")
    app.open(.history)
    app.any("day-2026-11-09").required("the walking day")
    app.terminate()
    let reopened = Gymemo.launch(store: "log-walking", reset: false)
    reopened.staticTexts["20 min"].required("the saved duration")
  }

  func testLogsACustomActivityAtTheLargestTextSize() throws {
    let app = Gymemo.launch(store: "log-custom-activity", textSize: Gymemo.largestTextSize)
    app.buttons["add-first-exercise"].scrollAndTap(in: app)
    app.buttons["create-timed-activity"].scrollAndTap(in: app)
    app.textFields["timed-activity-name"].required("the activity name field").tap()
    app.typeText("Stretching")
    app.buttons["sheet-confirm"].required("Save").tap()
    let duration = app.textFields["activity-duration"].required("the duration field")
    XCTAssertFalse(app.textFields["activity-distance"].exists)
    try app.performAccessibilityAudit(for: .sufficientElementDescription)
    duration.scrollAndTap(in: app)
    app.typeText("12")
    app.hideKeyboard()
    app.buttons["sheet-confirm"].required("Save").tap()
    app.staticTexts["12 min"].required("the recorded duration")
  }

  func testChangesTheWeightUnitForTheExistingLog() {
    let app = Gymemo.launch(store: "log-units", sample: true, tab: "settings")
    app.any("weight-unit").scrollAndTap(in: app)
    let pounds = app.buttons["Pounds (lb)"].required("Pounds")
    capture("weight-unit-choice")
    pounds.tap()
    app.open(.log)
    let unit = app.any("unit-weight-Bench Press")
    XCTAssertEqual(unit.required("the unit of the weight field").label, "lb")
    app.open(.settings)
    app.any("weight-unit").scrollAndTap(in: app)
    app.buttons["Kilograms (kg)"].required("Kilograms").tap()
    app.open(.log)
    XCTAssertEqual(unit.required("the unit of the weight field").label, "kg")
  }
}
