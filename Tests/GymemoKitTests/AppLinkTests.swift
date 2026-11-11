import Foundation
import Testing

@testable import GymemoKit

struct AppLinkTests {
  @Test func theCanonicalLogLinkRoundTrips() throws {
    let url = try AppLink.log.url()
    #expect(url.absoluteString == "com.p4suta.gymemo://log")
    #expect(AppLink(url: url) == .log)
  }

  @Test func onlyTheParameterlessLogRouteIsAccepted() throws {
    let accepted = try #require(URL(string: "COM.P4SUTA.GYMEMO://LOG"))
    #expect(AppLink(url: accepted) == .log)
    for text in [
      "https://log", "com.p4suta.other://log", "com.p4suta.gymemo://history",
      "com.p4suta.gymemo://log/", "com.p4suta.gymemo://log/delete",
      "com.p4suta.gymemo://log?", "com.p4suta.gymemo://log?day=2026-11-09",
      "com.p4suta.gymemo://log#", "com.p4suta.gymemo://log#delete",
      "com.p4suta.gymemo://person@log", "com.p4suta.gymemo://:password@log",
      "com.p4suta.gymemo://log:80", "log", "//log", "com.p4suta.gymemo:log",
    ] {
      let url = try #require(URL(string: text))
      #expect(AppLink(url: url) == nil, "\(text)")
    }
  }

  @Test func relativeReferencesCannotInheritThePrivateRouteFromABaseURL() throws {
    let base = try AppLink.log.url()
    let url = try #require(URL(string: "//log", relativeTo: base))
    #expect(AppLink(url: url) == nil)
    #expect(AppLink(url: url.absoluteURL) == .log)
  }
}
