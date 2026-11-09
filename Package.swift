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
    .testTarget(name: "GymemoCoreTests", dependencies: ["GymemoCore"]),
    .testTarget(name: "GymemoKitTests", dependencies: ["GymemoKit"]),
  ],
  swiftLanguageModes: [.v6]
)
