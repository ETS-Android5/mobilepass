// swift-tools-version:5.3
import PackageDescription
let package = Package(
    name: "MobilePassSDK",
	platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "MobilePassSDK",
            targets: ["MobilePassSDK"]),
    ],
    targets: [
        .binaryTarget(
            name: "MobilePassSDK",
            url: "https://customers.pspdfkit.com/pspdfkit/xcframework/10.2.1.zip",
            checksum: "f0952cbdf3dfb4af7c2b7a2286a4218a1dca85e275eee8a78a620a0acf8a73aa"),
    ]
)