//
//  Package.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TildoneCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TildoneDomain", targets: ["TildoneDomain"]),
        .library(name: "TildonePersistence", targets: ["TildonePersistence"]),
        .library(name: "TildoneSync", targets: ["TildoneSync"])
    ],
    targets: [
        .target(name: "TildoneDomain"),
        .target(name: "TildonePersistence", dependencies: ["TildoneDomain"]),
        .target(name: "TildoneSync", dependencies: ["TildoneDomain"]),
        .testTarget(name: "TildoneDomainTests", dependencies: ["TildoneDomain"]),
        .testTarget(name: "TildonePersistenceTests", dependencies: ["TildonePersistence"]),
        .testTarget(name: "TildoneSyncTests", dependencies: ["TildoneSync"])
    ]
)
