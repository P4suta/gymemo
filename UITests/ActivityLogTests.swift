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
    let app = Gymemo.launch(
      store: "log-units", sample: true, tab: "settings", usesStoredWeightUnit: true)
    app.buttons["open-units"].scrollAndTap(in: app)
    let pounds = app.buttons["Pounds (lb)"]
    pounds.scrollAndTap(in: app)
    capture("weight-unit-choice")
    app.open(.log)
    let unit = app.any("unit-weight-Bench Press")
    XCTAssertEqual(unit.required("the unit of the weight field").label, "lb")
    let rows = app.rows("Bench Press")
    rows.log(weight: "100", reps: "6")
    rows.set(4).required("the logged 100-pound set")
    app.open(.settings)
    app.buttons["Kilograms (kg)"].scrollAndTap(in: app)
    app.open(.log)
    XCTAssertEqual(unit.required("the unit of the weight field").label, "kg")
    XCTAssertEqual(rows.weight.value as? String, "45.36")
    XCTAssertEqual(rows.reps.value as? String, "6")

    app.fill("weight-Bench Press", with: "1000")
    app.open(.settings)
    pounds.scrollAndTap(in: app)
    app.open(.log)
    XCTAssertEqual(unit.required("the unit of the invalid weight field").label, "kg")
    XCTAssertEqual(rows.weight.value as? String, "1000")
  }

  func testSelectsUnitsAtTheLargestTextSize() {
    let app = Gymemo.launch(
      store: "large-unit-choices", tab: "settings", textSize: Gymemo.largestTextSize,
      usesStoredWeightUnit: true)
    app.buttons["open-units"].scrollAndTap(in: app)
    let pounds = app.buttons["Pounds (lb)"]
    let miles = app.buttons["Miles (mi)"]
    defer {
      app.buttons["Kilograms (kg)"].scrollAndTap(in: app)
      app.buttons["Kilometers (km)"].scrollAndTap(in: app)
    }
    pounds.scrollAndTap(in: app)
    XCTAssertTrue(pounds.isSelected)
    miles.scrollAndTap(in: app)
    XCTAssertTrue(miles.isSelected)
  }
}
