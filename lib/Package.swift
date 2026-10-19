// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "InricoB02PTTKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "InricoB02PTTKit",
            targets: ["InricoB02PTTKit"]
        )
    ],
    targets: [
        .target(
            name: "InricoB02PTTKit",
            path: "InricoB02PTTKit/Sources/InricoB02PTTKit"
        )
    ]
)
