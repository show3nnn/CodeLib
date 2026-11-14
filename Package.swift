// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodePath",
    platforms: [.macOS(.v26)],
    products: [.library(name: "LearningCore", targets: ["LearningCore"]),
               .library(name: "ExecutionSupport", targets: ["ExecutionSupport"]),
               .executable(name: "CodelibExecutionHelper", targets: ["CodelibExecutionHelper"]),
               .executable(name: "CodePath", targets: ["CodePathApp"])],
    targets: [
        .target(name: "LearningCore", resources: [.process("Resources")]),
        .target(name: "ExecutionSupport"),
        .executableTarget(name: "CodelibExecutionHelper", dependencies: ["ExecutionSupport"], path: "Sources/ExecutionHelper"),
        .executableTarget(name: "CodePathApp", dependencies: ["LearningCore", "ExecutionSupport"], path: "Sources/CodePath"),
        .testTarget(name: "ExecutionSupportTests", dependencies: ["ExecutionSupport"]),
        .testTarget(name: "LearningCoreTests", dependencies: ["LearningCore"]),
        .testTarget(name: "CodePathAppTests", dependencies: ["CodePathApp"])
    ]
)
