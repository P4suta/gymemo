import XCTest

@MainActor
enum PrivacyTour {
  static let facts = [
    "privacy-collection", "privacy-retention", "privacy-watch", "privacy-sync",
    "privacy-backup", "privacy-files", "privacy-deletion", "privacy-erase-devices",
    "privacy-delete-copies",
  ]

  static func read(in app: XCUIApplication) {
    read(in: app) { _ in }
  }

  static func read(in app: XCUIApplication, afterPage: (Int) throws -> Void) rethrows {
    var unread = Set(facts)
    var page = 0
    var swipesWithoutReading = 0
    while swipesWithoutReading < 12 {
      let viewport = ContentViewport(app).frame
      let reached = unread.filter { identifier in
        let text = app.any(identifier)
        return text.exists && text.isHittable && !text.label.isEmpty
          && viewport.contains(text.frame)
      }
      // Audits can reset the scroll position, so only audit newly reached content.
      if !reached.isEmpty {
        unread.subtract(reached)
        swipesWithoutReading = 0
        try afterPage(page)
        page += 1
        if unread.isEmpty { return }
      }
      if let identifier = facts.first(where: unread.contains) {
        let text = app.any(identifier)
        if text.exists {
          let distance = min(
            viewport.height / 2, max(-viewport.height / 2, viewport.midY - text.frame.midY))
          let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: viewport.midX - app.frame.minX, dy: viewport.midY - app.frame.minY))
          start.press(
            forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
            withVelocity: .slow, thenHoldForDuration: 0.1)
        } else {
          app.swipeUp(velocity: .slow)
        }
        swipesWithoutReading += 1
      }
    }
    XCTContext.runActivity(named: "Unreachable privacy facts") { activity in
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "privacy-hierarchy"
      hierarchy.lifetime = .keepAlways
      activity.add(hierarchy)
      let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      screenshot.name = "privacy-unreachable"
      screenshot.lifetime = .keepAlways
      activity.add(screenshot)
    }
    XCTFail("Privacy facts were not accessible: \(unread.sorted().joined(separator: ", "))")
  }

  static func audit(
    test: XCTestCase, prefix: String, audits: XCUIAccessibilityAuditType
  ) throws {
    let sizes: [String?] = [nil, Gymemo.largestTextSize]
    for language in ["en", "ja", "zh-Hans", "zh-Hant"] {
      for size in sizes {
        let name = "\(prefix)-\(language)-\(size == nil ? "default" : "largest")"
        try ScreenTour(
          test: test, prefix: name, language: language, textSize: size,
          audits: size == nil ? audits.subtracting(.textClipped) : audits
        ).runPrivacy()
      }
    }
  }
}
