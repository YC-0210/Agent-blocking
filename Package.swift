// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "DOCardAgentFocus",
  platforms: [.macOS(.v14), .iOS(.v18)],
  products: [.library(name: "AgentFocusCore", targets: ["AgentFocusCore"])],
  targets: [
    .target(name: "AgentFocusCore", path: "DoCard/AgentFocus/Core"),
    .testTarget(name: "AgentFocusTests", dependencies: ["AgentFocusCore"], path: "AgentFocusTests"),
  ]
)
