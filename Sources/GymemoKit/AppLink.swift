import Foundation

public enum AppLink: Equatable, Sendable {
  case log

  public static let scheme = "com.p4suta.gymemo"

  public init?(url: URL) {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme?.lowercased() == Self.scheme,
      components.host?.lowercased() == "log",
      components.user == nil, components.password == nil, components.port == nil,
      components.path.isEmpty, components.query == nil, components.fragment == nil
    else { return nil }
    self = .log
  }

  public func url() throws -> URL {
    var components = URLComponents()
    components.scheme = Self.scheme
    components.host =
      switch self {
      case .log: "log"
      }
    guard let url = components.url else { throw URLError(.badURL) }
    return url
  }
}
