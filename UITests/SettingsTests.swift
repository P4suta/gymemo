import XCTest

final class SettingsTests: XCTestCase {
  @MainActor
  func testOpensShortcutsAndReturnsToTheSettingsScreen() {
    let app = Gymemo.launch(store: "settings-shortcuts", tab: "settings")
    app.any("open-shortcuts").scrollAndTap(in: app)
    let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    XCTAssertTrue(shortcuts.wait(for: .runningForeground, timeout: 10))
    app.activate()
    app.any("open-shortcuts").required("the Shortcuts link after returning")
  }

  @MainActor
  func testReadsThePrivacyPolicyWithoutLeavingTheApp() {
    let app = Gymemo.launch(store: "settings-privacy", tab: "settings")
    app.buttons["open-privacy"].required("the privacy policy row").tap()
    app.navigationBars["Privacy Policy"].required("the privacy policy")
    PrivacyTour.read(in: app)
    app.goBack()
    app.buttons["open-privacy"].required("the settings screen")
  }

  @MainActor
  func testReadsEveryPrivacyFactAtTheLargestTextSizeInTraditionalChinese() {
    let app = Gymemo.launch(
      store: "settings-privacy-zh-hant-large", tab: "settings",
      textSize: Gymemo.largestTextSize, language: "zh-Hant")
    app.buttons["open-privacy"].scrollAndTap(in: app)
    PrivacyTour.read(in: app) { page in
      capture("privacy-zh-hant-large-\(page)")
    }
  }

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
    app.replaceText(of: "exercise-name", with: "Cable Fly")
    let bodyPart = app.buttons["body-part"].required("the body part menu")
    XCTAssertTrue(bodyPart.label.contains("Chest") || (bodyPart.value as? String) == "Chest")
    bodyPart.tap()
    app.buttons["Arms"].required("the body parts").tap()
    app.buttons["sheet-confirm"].tap()
    app.buttons["manage-Cable Fly"].scrollAndTap(in: app)
    app.textFields["exercise-name"].required("the editor of the new exercise")
    app.buttons["sheet-cancel"].tap()

    app.buttons["create-exercise"].tap()
    app.replaceText(of: "exercise-name", with: "Cable Fly")
    app.buttons["sheet-confirm"].tap()
    XCTAssertTrue(
      app.any("problem").required("the duplicate problem").label
        .hasPrefix("Another exercise already has that name."))
    app.buttons["sheet-cancel"].tap()
    app.buttons["Discard Changes"].required("the question before discarding").tap()

    app.buttons["manage-Cable Fly"].scrollAndTap(in: app)
    app.replaceText(of: "exercise-name", with: "Cable Crossover")
    app.switches["selectable"].required("the switch").switches.firstMatch.tap()
    app.buttons["sheet-confirm"].tap()
    let renamed = app.buttons["manage-Cable Crossover"].required("the renamed exercise")
    XCTAssertTrue(renamed.label.contains("Hidden"))

    app.open(.log)
    app.buttons["add-exercise"].required("the add button").tap()
    app.buttons["pick-Bench Press"].required("the picker")
    let search = app.searchFields.firstMatch.required("the search field")
    search.tap()
    search.typeText("Cable")
    app.buttons["pick-Bench Press"].requiredGone("the exercises that the search leaves out")
    XCTAssertFalse(app.buttons["pick-Cable Crossover"].exists)
  }

  @MainActor
  func testDeletesAnUnusedExerciseOnlyAfterConfirmation() {
    let app = Gymemo.launch(store: "settings-delete")
    let bench = app.addExercise("Bench Press")
    bench.log(weight: "60", reps: "10")
    bench.set(1).required("the logged set")
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
    app.buttons["delete-exercise"].required("the delete button").tap()
    app.buttons["Delete"].required("the confirmation")
    app.textFields["exercise-name"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .tap()
    app.buttons["Delete"].requiredGone("the dismissed confirmation")
    app.hideKeyboard()
    app.buttons["sheet-cancel"].tap()
    app.buttons["manage-Dips"].required("the kept exercise")

    app.buttons["manage-Dips"].scrollAndTap(in: app)
    app.buttons["delete-exercise"].required("the delete button").tap()
    app.buttons["Delete"].required("the confirmation").tap()
    app.buttons["manage-Dips"].requiredGone("the deleted exercise")
  }

  @MainActor
  func testShowsWhereRecordsAreKeptAndTheBackupActions() throws {
    let app = Gymemo.launch(store: "settings-backup", tab: "settings")
    app.staticTexts["Where Records Are Kept"].required("the storage heading")
    let version = app.staticTexts["app-version"].required("the app version")
    XCTAssertEqual(version.label, "Version")
    let information = try XCTUnwrap(Bundle(for: Self.self).infoDictionary)
    let release = try XCTUnwrap(information["CFBundleShortVersionString"] as? String)
    let build = try XCTUnwrap(information["CFBundleVersion"] as? String)
    XCTAssertEqual(version.value as? String, "\(release) (\(build))")
    app.buttons["open-backup"].tap()
    for action in ["export-backup", "export-csv", "import-backup"] {
      app.buttons[action].required(action)
    }
  }
}
