// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Gymemo",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "GymemoCore", targets: ["GymemoCore"]),
    .library(name: "GymemoKit", targets: ["GymemoKit"]),
  ],
  targets: [
    .target(name: "GymemoCore"),
    .systemLibrary(name: "CSQLite"),
    .target(name: "GymemoKit", dependencies: ["GymemoCore", "CSQLite"]),
    .target(
      name: "GymemoTestSupport", dependencies: ["GymemoCore"], path: "Tests/GymemoTestSupport"),
    .testTarget(name: "GymemoCoreTests", dependencies: ["GymemoCore", "GymemoTestSupport"]),
    .testTarget(name: "GymemoKitTests", dependencies: ["GymemoKit", "GymemoTestSupport"]),
  ],
  swiftLanguageModes: [.v6]
)
