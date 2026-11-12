import XCTest

final class LogTests: XCTestCase {
  @MainActor
  func testClearsAPrefilledFieldWithoutResizingItsRow() {
    let app = Gymemo.launch(store: "log-clear-field", sample: true)
    let bench = app.rows("Bench Press")
    let row = app.cells.containing(.textField, identifier: "reps-Bench Press").firstMatch
      .required("the repetitions row")
    let height = row.frame.height
    let clear = app.buttons["clear-reps-Bench Press"]
    XCTAssertFalse(clear.exists && clear.isHittable)

    bench.reps.scrollAndTap(in: app)
    clear.requiredHittable("the clear repetitions button")
    XCTAssertEqual(row.frame.height, height, accuracy: 1)
    XCTAssertLessThanOrEqual(clear.frame.maxY, app.toolbars.firstMatch.frame.minY)
    capture("log-number-field-clear")
    clear.tap()
    XCTAssertTrue(clear.waitForNonExistence(timeout: 5))
    XCTAssertFalse(clear.isHittable)
    XCTAssertEqual(bench.reps.value as? String, bench.reps.placeholderValue)
    XCTAssertEqual(bench.weight.value as? String, "63.75")
    XCTAssertEqual(row.frame.height, height, accuracy: 1)
  }

  @MainActor
  func testNumberSteppersExposeTheirCurrentValues() {
    let app = Gymemo.launch(store: "log-stepper-values", sample: true)
    let weight = app.steppers["step-weight-Bench Press"].required("the weight stepper")
    let reps = app.steppers["step-reps-Bench Press"].required("the repetitions stepper")
    XCTAssertEqual(weight.value as? String, "63.75 kg")
    XCTAssertEqual(reps.value as? String, "6 reps")
    weight.buttons["step-weight-Bench Press-Increment"].tap()
    XCTAssertEqual(weight.value as? String, "66.25 kg")
  }

  @MainActor
  func testLogsSetsFromAnEmptyDayAndKeepsThemAfterARelaunch() {
    var app = Gymemo.launch(store: "log-flow")
    app.any("empty-day").required("the empty day's guidance")
    var bench = app.addExercise("Bench Press")
    XCTAssertFalse(app.any("empty-day").exists)
    bench.log(weight: "60", reps: "10")
    XCTAssertEqual(
      bench.set(1).required("the first set").label, "Set 1, 60 kilograms, 10 reps")
    XCTAssertEqual(bench.weight.value as? String, "60")
    XCTAssertEqual(bench.reps.value as? String, "10")
    bench.logButton.scrollAndTap(in: app)
    XCTAssertEqual(
      bench.set(2).required("the second set").label, "Set 2, 60 kilograms, 10 reps")

    app.terminate()
    app = Gymemo.launch(store: "log-flow", reset: false)
    bench = app.rows("Bench Press")
    bench.set(1).required("the first set after a relaunch")
    XCTAssertTrue(bench.set(2).exists)
    XCTAssertFalse(bench.set(3).exists)
  }

  @MainActor
  func testShowsTheProblemUnderTheFieldsUntilTheInputIsFixed() {
    let app = Gymemo.launch(store: "log-problem")
    let squat = app.addExercise("Squat")
    squat.logButton.scrollAndTap(in: app)
    XCTAssertEqual(squat.problem.required("the problem").label, "Enter the reps.")
    XCTAssertFalse(squat.set(1).exists)

    app.fill("reps-Squat", with: "5")
    squat.logButton.scrollAndTap(in: app)
    XCTAssertEqual(
      squat.set(1).required("the bodyweight set").label, "Set 1, Bodyweight, 5 reps")
    squat.problem.requiredGone("the problem")

    app.fill("weight-Squat", with: "1000")
    squat.logButton.scrollAndTap(in: app)
    XCTAssertTrue(squat.problem.required("the weight problem").label.contains("0 to 999.99"))
    XCTAssertFalse(squat.set(2).exists)
  }

  @MainActor
  func testChangesCancelsAndDeletesASet() {
    let app = Gymemo.launch(store: "log-edit")
    let bench = app.addExercise("Bench Press")
    bench.log(weight: "60", reps: "10")
    let set = bench.set(1).required("the set")

    set.tap()
    app.textFields["edit-reps"].required("the set editor")
    app.fill("edit-reps", with: "8")
    app.buttons["sheet-confirm"].tap()
    app.textFields["edit-reps"].requiredGone("the set editor")
    XCTAssertEqual(set.label, "Set 1, 60 kilograms, 8 reps")

    set.tap()
    app.textFields["edit-weight"].required("the set editor")
    app.fill("edit-weight", with: "70")
    app.buttons["sheet-cancel"].tap()
    app.buttons["Discard Changes"].required("the question before discarding").tap()
    app.textFields["edit-weight"].requiredGone("the set editor")
    XCTAssertEqual(set.label, "Set 1, 60 kilograms, 8 reps")

    set.tap()
    app.buttons["delete-set"].required("the delete button").tap()
    set.requiredGone("the deleted set")
    XCTAssertTrue(bench.weight.exists)
  }

  @MainActor
  func testDeletesASetFromItsSwipeActions() {
    let app = Gymemo.launch(store: "log-swipe")
    let bench = app.addExercise("Bench Press")
    bench.log(weight: "60", reps: "10")
    let set = bench.set(1).required("the set")
    set.swipeLeft()
    app.buttons["Edit"].required("the edit action")
    app.buttons["Delete"].required("the delete action").tap()
    set.requiredGone("the deleted set")
  }

  @MainActor
  func testStepsTheWeightAndTheRepetitionsWithoutTheKeyboard() {
    let app = Gymemo.launch(store: "log-step")
    let bench = app.addExercise("Bench Press")
    XCTAssertEqual(bench.weight.value as? String, bench.weight.placeholderValue)
    bench.stepper("weight").buttons.element(boundBy: 1).tap()
    XCTAssertEqual(bench.weight.value as? String, "2.5")
    bench.stepper("weight").buttons.element(boundBy: 1).tap()
    bench.stepper("weight").buttons.element(boundBy: 0).tap()
    XCTAssertEqual(bench.weight.value as? String, "2.5")
    bench.stepper("reps").buttons.element(boundBy: 1).tap()
    bench.stepper("reps").buttons.element(boundBy: 1).tap()
    XCTAssertEqual(bench.reps.value as? String, "2")
    bench.logButton.scrollAndTap(in: app)
    XCTAssertEqual(bench.set(1).required("the set").label, "Set 1, 2.5 kilograms, 2 reps")
  }

  @MainActor
  func testWritesChangesCancelsAndClearsANote() {
    let app = Gymemo.launch(store: "log-note")
    app.buttons["edit-note"].required("the note button").tap()
    let editor = app.textViews["note-editor"].required("the note editor")
    editor.tap()
    editor.typeText("Felt strong")
    app.buttons["sheet-confirm"].tap()
    XCTAssertEqual(app.staticTexts["note-text"].required("the note").label, "Felt strong")

    app.buttons["edit-note"].tap()
    editor.required("the note editor").tapAtEnd()
    editor.typeText(" today")
    app.buttons["sheet-cancel"].tap()
    app.buttons["Keep Editing"].required("the question before discarding").tap()
    editor.required("the note editor after keeping the changes")
    app.buttons["sheet-cancel"].tap()
    app.buttons["Discard Changes"].required("the question before discarding").tap()
    editor.requiredGone("the note editor")
    XCTAssertEqual(app.staticTexts["note-text"].label, "Felt strong")

    app.buttons["edit-note"].tap()
    editor.required("the note editor").tapAtEnd()
    editor.press(forDuration: 1)
    app.menuItems["Select All"].required("the text selection action").tap()
    editor.typeText(XCUIKeyboardKey.delete.rawValue)
    let cleared = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == ''"), object: editor)
    guard XCTWaiter.wait(for: [cleared], timeout: 5) == .completed else {
      XCTFail("the note editor did not clear")
      return
    }
    app.buttons["sheet-confirm"].tap()
    app.staticTexts["note-text"].requiredGone("the cleared note")
  }

  @MainActor
  func testFillsTheNextSetFromThePreviousOneAndMarksAPersonalBest() {
    let app = Gymemo.launch(store: "log-sample", sample: true)
    let bench = app.rows("Bench Press")
    XCTAssertTrue(
      bench.previous.required("the previous session").label
        .hasPrefix("Last time on Mon, Nov 2: 62.5 kg × 8"))
    XCTAssertTrue(bench.set(1).label.hasSuffix("Personal Best"))
    XCTAssertFalse(bench.set(2).label.contains("Personal Best"))
    XCTAssertEqual(bench.weight.value as? String, "63.75")
    XCTAssertEqual(bench.reps.value as? String, "6")

    bench.log(weight: "70", reps: "8")
    XCTAssertEqual(
      bench.set(4).required("the new set").label,
      "Set 4, 70 kilograms, 8 reps, Personal Best")
  }
}
