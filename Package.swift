// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DragAndAsk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DragAndAsk",
            path: "Sources/DragAndAsk"
        )
    ]
)
