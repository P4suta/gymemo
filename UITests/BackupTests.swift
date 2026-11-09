import XCTest

final class BackupTests: XCTestCase {
  /// Exports the log through the system's file picker, changes the log, and replaces it with the exported file.
  @MainActor
  func testExportsABackupAndReplacesTheLogWithIt() {
    let app = Gymemo.launch(store: "backup-roundtrip")
    let bench = app.addExercise("Bench Press")
    bench.logSet(weight: "60", reps: "10", in: app)
    bench.buttons["set-1"].required("the logged set")

    app.open(.settings)
    app.buttons["open-backup"].required("the backup row").tap()
    app.buttons["export-backup"].required("the export button").tap()
    let save = app.buttons["Save"].firstMatch
    if !save.waitForExistence(timeout: 15) {
      let attachment = XCTAttachment(string: app.debugDescription)
      attachment.name = "export-picker-hierarchy"
      attachment.lifetime = .keepAlways
      add(attachment)
      capture("export-picker")
      XCTFail("The export picker showed no Save button")
      return
    }
    save.tap()
    let replace = app.buttons["Replace"].firstMatch
    if replace.waitForExistence(timeout: 3) { replace.tap() }
    XCTAssertEqual(
      app.staticTexts["backup-notice"].required("the export notice").label,
      "The file was exported.")

    app.open(.log)
    bench.buttons["log-set"].scrollAndTap(in: app)
    bench.buttons["set-2"].required("the second set")

    app.open(.settings)
    app.buttons["import-backup"].required("the import button").tap()
    let file = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@", "gymemo-backup-2026-11-09")
    ).firstMatch
    if !file.waitForExistence(timeout: 15) {
      let attachment = XCTAttachment(string: app.debugDescription)
      attachment.name = "import-picker-hierarchy"
      attachment.lifetime = .keepAlways
      add(attachment)
      capture("import-picker")
      XCTFail("The import picker showed no exported backup")
      return
    }
    file.tap()
    let alert = app.alerts["Replace the current records?"].required("the confirmation")
    XCTAssertTrue(
      alert.staticTexts[
        "Your 2 sets will be deleted and replaced with the 1 set in the backup. You can't undo the replacement."
      ].exists)
    alert.buttons["Cancel"].tap()
    app.open(.log)
    XCTAssertTrue(bench.buttons["set-2"].exists)

    app.open(.settings)
    app.buttons["import-backup"].required("the import button").tap()
    file.required("the exported backup", timeout: 15).tap()
    app.alerts["Replace the current records?"].required("the confirmation").buttons["Replace"]
      .tap()
    XCTAssertEqual(
      app.staticTexts["backup-notice"].required("the import notice").label,
      "The backup was imported.")
    app.open(.log)
    bench.buttons["set-2"].requiredGone("the set that the backup doesn't hold")
  }
}
