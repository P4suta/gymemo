import XCTest

final class HistoryTests: XCTestCase {
  @MainActor
  func testAnEmptyHistoryLeadsToTodaysLog() {
    let app = Gymemo.launch(store: "history-empty", tab: "history")
    app.any("empty-history").required("the empty history's guidance")
    app.buttons["start-today"].tap()
    app.any("empty-day").required("today's log")
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
    app.staticTexts["You are viewing a day other than today."].required("the past day notice")
    let squat = app.addExercise("Squat")
    squat.log(weight: "100", reps: "5")
    squat.set(1).required("the logged set")
    app.goBack()
    let row = app.buttons["day-2026-11-05"].required("the past day in the history")
    XCTAssertTrue(row.label.contains("Squat"))
    XCTAssertTrue(row.label.contains("1 set"))
    app.staticTexts["November 2026"].required("the header of the month")
  }

  @MainActor
  func testCancellingTheDayPickerOpensNothing() {
    let app = Gymemo.launch(store: "history-cancel", tab: "history")
    app.buttons["log-another-day"].required("the day button").tap()
    app.datePickers.firstMatch.required("the day picker")
    app.buttons["sheet-cancel"].tap()
    app.any("empty-history").required("the unchanged history")
    XCTAssertFalse(app.any("empty-day").exists)
  }

  @MainActor
  func testReachesTheOldestDayByScrolling() {
    let app = Gymemo.launch(store: "history-older", sample: true, tab: "history")
    app.buttons["day-2026-11-09"].required("the newest day")
    let oldest = app.buttons["day-2026-09-21"]
    var swipes = 0
    while !oldest.exists, swipes < 12 {
      app.swipeUp()
      swipes += 1
    }
    oldest.required("the oldest day")
    app.staticTexts["September 2026"].required("the header of the oldest month")
  }

  @MainActor
  func testOpensADayFromTheListAndAddsToIt() {
    let app = Gymemo.launch(store: "history-open", sample: true, tab: "history")
    let row = app.buttons["day-2026-11-06"].required("a sample day")
    XCTAssertTrue(row.label.contains("Deadlift, Lat Pulldown"))
    XCTAssertTrue(row.label.contains("5 sets"))
    XCTAssertTrue(app.buttons["day-2026-11-04"].label.contains("Shoulder felt tight"))
    row.tap()
    let deadlift = app.rows("Deadlift")
    deadlift.logButton.scrollAndTap(in: app)
    deadlift.set(3).required("the added set")
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
    app.any("empty-analysis").required("the empty analysis guidance")
    app.buttons["start-today"].tap()
    app.any("empty-day").required("today's log")
  }

  @MainActor
  func testShowsWeeklyTrainingDaysAndTheProgressOfAnExercise() {
    let app = Gymemo.launch(store: "analysis-sample", sample: true, tab: "analysis")
    XCTAssertEqual(
      app.staticTexts["weekly-headline"].required("the weekly headline").label,
      "1 day this week, 3 days last week")
    XCTAssertTrue(app.any("weekly-chart").exists)
    let bench = app.buttons["progress-Bench Press"].required("the bench press row")
    XCTAssertTrue(bench.label.contains("Estimated 1RM 80.8 kg"))
    XCTAssertTrue(app.buttons["progress-Pull-Up"].label.contains("Most Reps 9"))
    bench.scrollAndTap(in: app)

    XCTAssertEqual(
      app.staticTexts["best-score"].required("the best score").label, "Estimated 1RM 80.8 kg")
    app.staticTexts["63.75 kg × 8 on Mon, Nov 9, 2026"].firstMatch.required("the best set")
    app.staticTexts["Heaviest Weight 63.75 kg"].required("the heaviest weight")
    let chart = app.any("progress-chart").required("the progress chart")
    let observed = [
      ("Mon, Sep 21, 2026", "69.7 kg"), ("Mon, Sep 28, 2026", "71.3 kg"),
      ("Mon, Oct 5, 2026", "72.8 kg"), ("Mon, Oct 12, 2026", "74.4 kg"),
      ("Mon, Oct 19, 2026", "76 kg"), ("Mon, Oct 26, 2026", "77.6 kg"),
      ("Mon, Nov 2, 2026", "79.2 kg"), ("Mon, Nov 9, 2026", "80.8 kg"),
    ]
    for (date, score) in observed {
      let points = chart.descendants(matching: .any).matching(
        NSPredicate(format: "label == %@ AND value == %@", date, score))
      XCTAssertEqual(points.count, 1, "\(date): \(score)")
    }
    let trend = app.staticTexts["progress-trend-description"].required("the dashed trend")
    XCTAssertEqual(trend.label, "The dashed trend goes from 69.7 kg to 80.8 kg.")
    let range = app.segmentedControls.firstMatch.required("the range control")
    XCTAssertTrue(range.buttons["3 Months"].isSelected)
    range.buttons["All"].tap()
    XCTAssertTrue(range.buttons["All"].isSelected)
    XCTAssertFalse(range.buttons["3 Months"].isSelected)
    app.any("progress-chart").required("the chart of every period")
    app.goBack()
    app.staticTexts["weekly-headline"].required("the analysis list")
  }

  @MainActor
  func testShowsAnIsolatedHighScoreAndKeepsTheTrend() {
    let app = Gymemo.launch(store: "analysis-spike", sample: true, tab: "history")
    app.buttons["day-2026-10-12"].scrollAndTap(in: app)
    app.buttons["set-1-Bench Press"].scrollAndTap(in: app)
    app.fill("edit-weight", with: "200")
    app.buttons["sheet-confirm"].tap()

    app.open(.analysis)
    app.buttons["progress-Bench Press"].scrollAndTap(in: app)
    let chart = app.any("progress-chart").required("the progress chart")
    let spike = chart.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@ AND value == %@", "Mon, Oct 12, 2026", "253.3 kg"))
    XCTAssertEqual(spike.count, 1)
    let trend = app.staticTexts["progress-trend-description"].required("the dashed trend")
    XCTAssertEqual(trend.label, "The dashed trend goes from 69.7 kg to 80.8 kg.")
    capture("progress-isolated-spike")
  }
}
