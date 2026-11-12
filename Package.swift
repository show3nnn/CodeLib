// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodePath",
    platforms: [.macOS(.v26)],
    products: [.library(name: "LearningCore", targets: ["LearningCore"]),
               .executable(name: "CodePath", targets: ["CodePathApp"])],
    targets: [
        .target(name: "LearningCore", resources: [.process("Resources")]),
        .executableTarget(name: "CodePathApp", dependencies: ["LearningCore"], path: "Sources/CodePath"),
        .testTarget(name: "LearningCoreTests", dependencies: ["LearningCore"]),
        .testTarget(name: "CodePathAppTests", dependencies: ["CodePathApp"])
    ]
)
