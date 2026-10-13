// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "NIKADesktop", platforms: [.macOS(.v14)],
    products: [.executable(name: "NIKADesktop", targets: ["NIKADesktop"])],
    dependencies: [.package(url: "https://github.com/stasel/WebRTC.git", exact: "154.0.0")],
    targets: [.executableTarget(name: "NIKADesktop", dependencies: [.product(name: "WebRTC", package: "WebRTC")], resources: [.copy("Resources/Mascot")]),
              .testTarget(name: "NIKADesktopTests", dependencies: ["NIKADesktop"])],
    swiftLanguageModes: [.v5]
)
