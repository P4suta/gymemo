// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Gymemo",
  defaultLocalization: "en",
  platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .visionOS(.v26)],
  products: [
    .library(name: "GymemoCore", targets: ["GymemoCore"]),
    .library(name: "GymemoKit", targets: ["GymemoKit"]),
    .library(name: "GymemoCopy", targets: ["GymemoCopy"]),
  ],
  targets: [
    .target(name: "GymemoCore"),
    .systemLibrary(name: "CSQLite"),
    .target(name: "GymemoKit", dependencies: ["GymemoCore", "CSQLite"]),
    .target(
      name: "GymemoCopy", dependencies: ["GymemoCore", "GymemoKit"],
      resources: [.process("Localizable.xcstrings")]),
    .target(
      name: "GymemoTestSupport", dependencies: ["GymemoCore"], path: "Tests/GymemoTestSupport"),
    .testTarget(name: "GymemoCopyTests", dependencies: ["GymemoCopy"]),
    .testTarget(name: "GymemoCoreTests", dependencies: ["GymemoCore", "GymemoTestSupport"]),
    .testTarget(name: "GymemoKitTests", dependencies: ["GymemoKit", "GymemoTestSupport"]),
  ],
  swiftLanguageModes: [.v6]
)
