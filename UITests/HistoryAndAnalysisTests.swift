import XCTest

final class HistoryTests: XCTestCase {
  @MainActor
  func testAnEmptyHistoryLeadsToTodaysLog() {
    let app = Gymemo.launch(store: "history-empty", tab: "history")
    app.staticTexts["empty-history"].required("the empty history's guidance")
    app.buttons["start-today"].tap()
    app.staticTexts["empty-day"].required("today's log")
    XCTAssertTrue(app.tabBars.buttons["Log"].isSelected)
  }

  @MainActor
  func testLogsAPastDayThroughTheDayPicker() {
    let app = Gymemo.launch(store: "history-past", tab: "history")
    app.buttons["log-another-day"].required("the day button").tap()
    let fifth = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "November 5"))
      .firstMatch
    fifth.required("November 5 in the day picker").tap()
    app.buttons["sheet-confirm"].tap()
    app.navigationBars["Thu, Nov 5, 2026"].required("the chosen day's title")
    app.staticTexts["You are viewing a day other than today"].required("the past day notice")
    let squat = app.addExercise("Squat")
    squat.logSet(weight: "100", reps: "5", in: app)
    squat.buttons["set-1"].required("the logged set")
    app.goBack()
    let row = app.buttons["day-2026-11-05"].required("the past day in the history")
    XCTAssertTrue(row.label.contains("Squat"))
    XCTAssertTrue(row.label.contains("1 set"))
  }

  @MainActor
  func testCancellingTheDayPickerOpensNothing() {
    let app = Gymemo.launch(store: "history-cancel", tab: "history")
    app.buttons["log-another-day"].required("the day button").tap()
    app.datePickers.firstMatch.required("the day picker")
    app.buttons["sheet-cancel"].tap()
    app.staticTexts["empty-history"].required("the unchanged history")
    XCTAssertFalse(app.staticTexts["empty-day"].exists)
  }

  @MainActor
  func testShowsOlderDaysOnRequest() {
    let app = Gymemo.launch(store: "history-older", sample: true, tab: "history")
    app.buttons["day-2026-11-09"].required("the newest day")
    XCTAssertFalse(app.buttons["day-2026-09-21"].exists)
    app.buttons["show-older-days"].scrollAndTap(in: app)
    app.buttons["day-2026-09-21"].required("the oldest day")
    XCTAssertFalse(app.buttons["show-older-days"].exists)
  }

  @MainActor
  func testOpensADayFromTheListAndAddsToIt() {
    let app = Gymemo.launch(store: "history-open", sample: true, tab: "history")
    let row = app.buttons["day-2026-11-06"].required("a sample day")
    XCTAssertTrue(row.label.contains("Deadlift, Lat Pulldown"))
    XCTAssertTrue(row.label.contains("5 sets"))
    XCTAssertTrue(app.buttons["day-2026-11-04"].label.contains("Shoulder felt tight"))
    row.tap()
    let deadlift = app.block("Deadlift").required("the deadlift section")
    deadlift.buttons["log-set"].scrollAndTap(in: app)
    deadlift.buttons["set-3"].required("the added set")
    app.goBack()
    XCTAssertTrue(app.buttons["day-2026-11-06"].required("the day").label.contains("6 sets"))
  }
}

final class AnalysisTests: XCTestCase {
  @MainActor
  func testAnEmptyAnalysisLeadsToTodaysLog() {
    let app = Gymemo.launch(store: "analysis-empty", tab: "analysis")
    XCTAssertEqual(
      app.staticTexts["weekly-headline"].required("the weekly headline").label,
      "0 days this week, 0 days last week")
    app.staticTexts["empty-analysis"].required("the empty analysis guidance")
    app.buttons["start-today"].tap()
    app.staticTexts["empty-day"].required("today's log")
  }

  @MainActor
  func testShowsWeeklyTrainingDaysAndTheProgressOfAnExercise() {
    let app = Gymemo.launch(store: "analysis-sample", sample: true, tab: "analysis")
    XCTAssertEqual(
      app.staticTexts["weekly-headline"].required("the weekly headline").label,
      "1 day this week, 3 days last week")
    XCTAssertTrue(app.otherElements["weekly-chart"].exists)
    let bench = app.buttons["progress-Bench Press"].required("the bench press row")
    XCTAssertTrue(bench.label.contains("Estimated 1RM 80.8 kg"))
    XCTAssertTrue(app.buttons["progress-Pull-Up"].label.contains("Most reps 9"))
    bench.scrollAndTap(in: app)

    XCTAssertEqual(
      app.staticTexts["best-score"].required("the best score").label, "Estimated 1RM 80.8 kg")
    app.staticTexts["63.75 kg × 8 on Mon, Nov 9, 2026"].firstMatch.required("the best set")
    app.staticTexts["Heaviest weight 63.75 kg"].required("the heaviest weight")
    app.otherElements["progress-chart"].required("the progress chart")
    XCTAssertTrue(app.buttons["range-threeMonths"].isSelected)
    app.buttons["range-all"].tap()
    XCTAssertTrue(app.buttons["range-all"].isSelected)
    XCTAssertFalse(app.buttons["range-threeMonths"].isSelected)
    app.otherElements["progress-chart"].required("the chart of every period")
    app.goBack()
    app.staticTexts["weekly-headline"].required("the analysis list")
  }
}
