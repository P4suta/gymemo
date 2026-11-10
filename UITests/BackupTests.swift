import XCTest

final class BackupTests: XCTestCase {
  /// Exports the log through the system's file picker, changes the log, and replaces it with the exported file.
  @MainActor
  func testExportsABackupAndReplacesTheLogWithIt() {
    let app = Gymemo.launch(store: "backup-roundtrip")
    let bench = app.addExercise("Bench Press")
    bench.log(weight: "60", reps: "10")
    bench.set(1).required("the logged set")

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
    // A file from an earlier run makes the picker ask before it replaces that file.
    // SpringBoard shows the question, so the app's own elements never include it.
    let notice = app.any("backup-notice")
    let replace = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Replace"]
      .firstMatch
    for _ in 0..<10 where !notice.waitForExistence(timeout: 2) {
      if replace.exists { replace.tap() }
    }
    if !notice.exists { capture("export-picker-after-save") }
    XCTAssertEqual(notice.required("the export notice").label, "The file was exported.")

    app.open(.log)
    bench.logButton.scrollAndTap(in: app)
    bench.set(2).required("the second set")

    app.open(.settings)
    app.buttons["import-backup"].required("the import button").tap()
    // The picker opens a file from a tap on its cell, and a tap on the name alone leaves the picker open.
    let file = exportedBackup(in: app)
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
    capture("import-picker-after-tap")
    let alert = app.alerts["Replace the current records?"].required("the confirmation")
    XCTAssertTrue(
      alert.staticTexts[
        "Your 2 sets will be deleted and replaced with the 1 set in the backup. You can't undo the replacement."
      ].exists)
    alert.buttons["Cancel"].tap()
    app.open(.log)
    XCTAssertTrue(bench.set(2).exists)

    app.open(.settings)
    app.buttons["import-backup"].required("the import button").tap()
    exportedBackup(in: app).required("the exported backup", timeout: 15).tap()
    app.alerts["Replace the current records?"].required("the confirmation").buttons["Replace"]
      .tap()
    XCTAssertEqual(
      app.any("backup-notice").required("the import notice").label,
      "The backup was imported.")
    app.open(.log)
    bench.set(2).requiredGone("the set that the backup doesn't hold")
  }

  /// The cell of the exported backup in the import picker, reached by the same way on every run.
  /// The picker opens where its last use ended, which may be an empty Recents tab.
  /// The test goes to the Browse tab and into the local folder of the device before it looks for the file.
  @MainActor
  private func exportedBackup(in app: XCUIApplication) -> XCUIElement {
    let file = app.cells.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "gymemo-backup-2026-11-09")
    ).firstMatch
    let browse = app.buttons["Browse"].firstMatch
    if browse.waitForExistence(timeout: 15) {
      browse.tap()
      if !file.waitForExistence(timeout: 3) {
        let local = app.staticTexts["On My iPhone"].firstMatch
        if local.waitForExistence(timeout: 5) { local.tap() }
      }
    }
    return file
  }
}
