// swift-tools-version:5.9
import PackageDescription

// Pins Trust Wallet Core's prebuilt xcframeworks by URL and checksum.
//
// Why this wrapper exists rather than depending on trustwallet/wallet-core
// directly: the Package.swift COMMITTED to that repository is stale. At tag
// 4.8.4 it still points at the 4.2.9 binaries, under an asset name
// (SwiftProtobuf.xcframework.zip) that release no longer publishes. Adding the
// package by version in Xcode therefore resolves 4.8.4 and installs 4.2.9,
// silently. The correct manifest ships as a release *asset*, not in the tree;
// the URLs and checksums below are copied from the 4.8.4 asset verbatim.
//
// This is a pin, not a fork: we carry no patched source, only two URLs and two
// checksums. SPM verifies both at resolve time, so a wrong value fails loudly
// rather than installing something unexpected.
//
// Both binary targets are required. WalletCore's signing inputs
// (EthereumSigningInput and friends) are generated protobuf types, so the
// SwiftProtobuf runtime must be linked alongside it. Consumers need only
// `import WalletCore`.
//
// To upgrade: download the Package.swift asset from the new release
//   gh release download <tag> --repo trustwallet/wallet-core --pattern Package.swift
// and copy its urls and checksums here. Do not read them from the repo tree.
let package = Package(
    name: "WalletCoreBinary",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "WalletCore", targets: ["WalletCore", "WalletCoreSwiftProtobuf"])
    ],
    targets: [
        .binaryTarget(
            name: "WalletCore",
            url: "https://github.com/trustwallet/wallet-core/releases/download/4.8.4/WalletCore.xcframework.zip",
            checksum: "3d70d9d988c253e13e65c6fa9947f5ed7c9e31ca55ff719d055646f11dd0287a"
        ),
        .binaryTarget(
            name: "WalletCoreSwiftProtobuf",
            url: "https://github.com/trustwallet/wallet-core/releases/download/4.8.4/WalletCoreSwiftProtobuf.xcframework.zip",
            checksum: "387fa8e0aad9470ce50efc17d3b9e736a747ded225b9e190385ad13636a0d300"
        )
    ]
)
