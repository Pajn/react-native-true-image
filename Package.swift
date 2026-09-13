// swift-tools-version:5.9
// Host-side unit tests for the pure geometry and policy code. The iOS
// build uses the podspec; this manifest only exists so `swift test` can run
// TrueImagePolicy without a simulator.
import PackageDescription

let package = Package(
  name: "TrueImagePolicy",
  platforms: [.macOS(.v13)],
  targets: [
    .target(
      name: "TrueImagePolicy",
      path: "ios",
      sources: ["TrueImagePolicy.swift"]
    ),
    .testTarget(
      name: "TrueImagePolicyTests",
      dependencies: ["TrueImagePolicy"],
      path: "ios/Tests"
    ),
  ]
)
