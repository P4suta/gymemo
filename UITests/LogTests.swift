import XCTest

final class LogTests: XCTestCase {
  @MainActor
  func testLogsSetsFromAnEmptyDayAndKeepsThemAfterARelaunch() {
    var app = Gymemo.launch(store: "log-flow")
    app.staticTexts["empty-day"].required("the empty day's guidance")
    var bench = app.addExercise("Bench Press")
    XCTAssertFalse(app.staticTexts["empty-day"].exists)
    bench.logSet(weight: "60", reps: "10", in: app)
    XCTAssertEqual(
      bench.buttons["set-1"].required("the first set").label, "Set 1, 60 kilograms, 10 reps")
    XCTAssertEqual(bench.textFields["weight"].value as? String, "60")
    XCTAssertEqual(bench.textFields["reps"].value as? String, "10")
    bench.buttons["log-set"].scrollAndTap(in: app)
    XCTAssertEqual(
      bench.buttons["set-2"].required("the second set").label, "Set 2, 60 kilograms, 10 reps")

    app.terminate()
    app = Gymemo.launch(store: "log-flow", reset: false)
    bench = app.block("Bench Press").required("the bench press section after a relaunch")
    XCTAssertTrue(bench.buttons["set-1"].exists)
    XCTAssertTrue(bench.buttons["set-2"].exists)
    XCTAssertFalse(bench.buttons["set-3"].exists)
  }

  @MainActor
  func testShowsTheProblemBesideTheFieldsUntilTheInputIsFixed() {
    let app = Gymemo.launch(store: "log-problem")
    let squat = app.addExercise("Squat")
    squat.buttons["log-set"].scrollAndTap(in: app)
    XCTAssertEqual(squat.staticTexts["problem"].required("the problem").label, "Enter the reps.")
    XCTAssertFalse(squat.buttons["set-1"].exists)

    app.fill("reps", with: "5", in: squat)
    squat.buttons["log-set"].scrollAndTap(in: app)
    XCTAssertEqual(
      squat.buttons["set-1"].required("the bodyweight set").label, "Set 1, Bodyweight, 5 reps")
    squat.staticTexts["problem"].requiredGone("the problem")

    app.fill("weight", with: "1000", in: squat)
    squat.buttons["log-set"].scrollAndTap(in: app)
    XCTAssertTrue(
      squat.staticTexts["problem"].required("the weight problem").label.contains("0 to 999.99"))
    XCTAssertFalse(squat.buttons["set-2"].exists)
  }

  @MainActor
  func testChangesCancelsAndDeletesASet() {
    let app = Gymemo.launch(store: "log-edit")
    let bench = app.addExercise("Bench Press")
    bench.logSet(weight: "60", reps: "10", in: app)
    let set = bench.buttons["set-1"].required("the set")

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
    app.textFields["edit-weight"].requiredGone("the set editor")
    XCTAssertEqual(set.label, "Set 1, 60 kilograms, 8 reps")

    set.tap()
    app.buttons["delete-set"].required("the delete button").tap()
    set.requiredGone("the deleted set")
    XCTAssertTrue(bench.exists)
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
    editor.requiredGone("the note editor")
    XCTAssertEqual(app.staticTexts["note-text"].label, "Felt strong")

    app.buttons["edit-note"].tap()
    editor.required("the note editor").tapAtEnd()
    let written = (editor.value as? String) ?? ""
    editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: written.count))
    app.buttons["sheet-confirm"].tap()
    app.staticTexts["note-text"].requiredGone("the cleared note")
  }

  @MainActor
  func testFillsTheNextSetFromThePreviousOneAndMarksAPersonalBest() {
    let app = Gymemo.launch(store: "log-sample", sample: true)
    let bench = app.block("Bench Press").required("the bench press section")
    XCTAssertTrue(
      bench.staticTexts["previous-session"].label.hasPrefix("Last time on Mon, Nov 2: 62.5 kg × 8"))
    XCTAssertTrue(bench.buttons["set-1"].label.hasSuffix("Personal Best"))
    XCTAssertFalse(bench.buttons["set-2"].label.contains("Personal Best"))
    XCTAssertEqual(bench.textFields["weight"].value as? String, "63.75")
    XCTAssertEqual(bench.textFields["reps"].value as? String, "6")

    bench.logSet(weight: "70", reps: "8", in: app)
    XCTAssertEqual(
      bench.buttons["set-4"].required("the new set").label,
      "Set 4, 70 kilograms, 8 reps, Personal Best")
  }
}
