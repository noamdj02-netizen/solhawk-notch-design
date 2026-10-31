// swift-tools-version: 6.0
import PackageDescription

// SolHawk Notch : petit compagnon d'encoche, LECTURE SEULE (GET sur l'API locale/HTTPS du companion). Aucune clé de portefeuille, aucun ordre.
let package = Package(
    name: "SolHawkNotch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SolHawkNotch", targets: ["SolHawkNotch"])],
    targets: [
        .target(name: "SolHawkNotchCore"),
        .executableTarget(name: "SolHawkNotch", dependencies: ["SolHawkNotchCore"]),
        .testTarget(name: "SolHawkNotchCoreTests", dependencies: ["SolHawkNotchCore"]),
    ]
)
