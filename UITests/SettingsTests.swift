import XCTest

final class SettingsTests: XCTestCase {
  @MainActor
  private func openExercises(_ app: XCUIApplication) {
    app.open(.settings)
    app.buttons["open-exercises"].required("the exercises row").tap()
    app.buttons["create-exercise"].required("the exercise list")
  }

  @MainActor
  func testCreatesRenamesAndHidesAnExercise() {
    let app = Gymemo.launch(store: "settings-exercises")
    openExercises(app)
    app.buttons["create-exercise"].tap()
    app.textFields["exercise-name"].required("the name field")
    app.fill("exercise-name", with: "Cable Fly")
    XCTAssertTrue(app.buttons["body-part-chest"].isSelected)
    app.buttons["body-part-arms"].scrollAndTap(in: app)
    XCTAssertTrue(app.buttons["body-part-arms"].isSelected)
    app.buttons["sheet-confirm"].tap()
    app.buttons["manage-Cable Fly"].required("the new exercise")

    app.buttons["create-exercise"].scrollAndTap(in: app)
    app.textFields["exercise-name"].required("the name field")
    app.fill("exercise-name", with: "Cable Fly")
    app.buttons["sheet-confirm"].tap()
    XCTAssertTrue(
      app.staticTexts["problem"].required("the duplicate problem").label
        .hasPrefix("Another exercise already has that name."))
    app.buttons["sheet-cancel"].tap()

    app.buttons["manage-Cable Fly"].scrollAndTap(in: app)
    app.textFields["exercise-name"].required("the name field")
    app.fill("exercise-name", with: "Cable Crossover")
    app.buttons["selectable"].scrollAndTap(in: app)
    app.buttons["sheet-confirm"].tap()
    let renamed = app.buttons["manage-Cable Crossover"].required("the renamed exercise")
    XCTAssertTrue(renamed.label.contains("Hidden"))

    app.open(.log)
    app.buttons["add-exercise"].scrollAndTap(in: app)
    app.buttons["pick-Bench Press"].required("the picker")
    XCTAssertFalse(app.buttons["pick-Cable Crossover"].exists)
    app.buttons["sheet-cancel"].tap()
  }

  @MainActor
  func testDeletesAnUnusedExerciseOnlyAfterConfirmation() {
    let app = Gymemo.launch(store: "settings-delete")
    let bench = app.addExercise("Bench Press")
    bench.logSet(weight: "60", reps: "10", in: app)
    bench.buttons["set-1"].required("the logged set")
    openExercises(app)

    app.buttons["manage-Bench Press"].scrollAndTap(in: app)
    app.textFields["exercise-name"].required("the editor")
    XCTAssertFalse(app.buttons["delete-exercise"].exists)
    XCTAssertTrue(
      app.staticTexts[
        "An exercise with logged sets can't be deleted. You can hide it when choosing an exercise instead."
      ]
      .exists)
    app.buttons["sheet-cancel"].tap()

    app.buttons["manage-Dips"].scrollAndTap(in: app)
    app.buttons["delete-exercise"].required("the delete button").scrollAndTap(in: app)
    app.buttons["Cancel"].firstMatch.required("the confirmation").tap()
    app.buttons["sheet-cancel"].tap()
    app.buttons["manage-Dips"].required("the kept exercise")

    app.buttons["manage-Dips"].scrollAndTap(in: app)
    app.buttons["delete-exercise"].required("the delete button").scrollAndTap(in: app)
    app.buttons["Delete"].firstMatch.required("the confirmation").tap()
    app.buttons["manage-Dips"].requiredGone("the deleted exercise")
  }

  @MainActor
  func testShowsWhereRecordsAreKeptAndTheBackupActions() {
    let app = Gymemo.launch(store: "settings-backup", tab: "settings")
    app.staticTexts["Where records are kept"].required("the storage heading")
    XCTAssertTrue(app.staticTexts["Version 1.0 (1)"].exists)
    app.buttons["open-backup"].tap()
    for action in ["export-backup", "export-csv", "import-backup"] {
      app.buttons[action].required(action)
    }
  }
}
