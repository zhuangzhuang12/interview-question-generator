// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InterviewDesk",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "InterviewDesk", targets: ["InterviewDesk"])
    ],
    targets: [
        .executableTarget(name: "InterviewDesk")
    ]
)
