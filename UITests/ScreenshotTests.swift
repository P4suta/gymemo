import XCTest

/// Walks the sample log through every screen and keeps a screenshot of each, for review.
@MainActor
enum ScreenTour {
  static func run(in test: XCTestCase, prefix: String, store: String) {
    let app = Gymemo.launch(store: store, sample: true)
    app.staticTexts["ベンチプレス"].required("the bench press section")
    test.capture("\(prefix)-01-log")

    app.buttons["種目を追加"].scrollAndTap(in: app)
    app.buttons["pick-スクワット"].required("the exercise picker")
    test.capture("\(prefix)-02-exercise-picker")
    app.buttons["キャンセル"].tap()

    app.tabBars.buttons["履歴"].tap()
    app.buttons["day-2026-11-06"].required("the history list")
    test.capture("\(prefix)-03-history")

    app.tabBars.buttons["分析"].tap()
    app.staticTexts["weekly-headline"].required("the weekly headline")
    test.capture("\(prefix)-04-analysis")
    app.buttons["progress-ベンチプレス"].scrollAndTap(in: app)
    app.staticTexts["best-score"].required("the best score")
    test.capture("\(prefix)-05-exercise-progress")

    app.tabBars.buttons["設定"].tap()
    app.buttons["種目の管理"].required("the settings list")
    test.capture("\(prefix)-06-settings")
    app.buttons["書き出しと読み込み"].tap()
    app.buttons["バックアップを書き出す"].required("the backup screen")
    test.capture("\(prefix)-07-backup")
  }
}

final class ScreenshotTests: XCTestCase {
  @MainActor
  func testCapturesEveryScreen() {
    ScreenTour.run(in: self, prefix: "light", store: "screenshots-light")
  }

  @MainActor
  func testCapturesTheLogAtTheLargestTextSize() {
    let app = Gymemo.launch(
      store: "screenshots-large", sample: true,
      textSize: "UICTContentSizeCategoryAccessibilityXXXL")
    app.staticTexts["ベンチプレス"].required("the bench press section")
    capture("large-01-log")
    app.swipeUp()
    capture("large-02-log-entry")
  }
}

/// The scenarios that the check command runs while the simulator shows the dark appearance.
final class DarkAppearanceTests: XCTestCase {
  @MainActor
  func testCapturesEveryScreen() {
    ScreenTour.run(in: self, prefix: "dark", store: "screenshots-dark")
  }
}
