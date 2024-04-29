// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "composable-avcapture-session",
    platforms: [.iOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "composable-avcapture-session",
            targets: ["ComposableAVCaptureSession"]),
    ],
    dependencies: [
      .package(
        url: "https://github.com/pointfreeco/swift-composable-architecture.git",
        from: "1.10.0"
      ),
      .package(
        url: "https://github.com/pointfreeco/swift-custom-dump.git",
        from: "1.1.2"
      ),
      .package(
        url: "https://github.com/pointfreeco/swift-perception.git",
        from: "1.1.0"
      ),
      .package(
        url: "https://github.com/pointfreeco/swift-dependencies.git",
        from: "1.1.5"
      )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
          name: "ComposableAVCaptureSession",
          dependencies: [
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
          ]),
        .testTarget(
            name: "ComposableAVCaptureSessionTests",
            dependencies: ["ComposableAVCaptureSession"]),
    ]
)
