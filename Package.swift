// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HoverTranslate",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "HoverTranslate", targets: ["HoverTranslate"])],
    targets: [
        .executableTarget(name: "HoverTranslate")
    ]
)
