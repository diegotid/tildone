//
//  SyncStatusMenu.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import Foundation
import SwiftUI
import TildoneSync

struct SyncStatusMenu: View {
    let status: SyncStatus
    let transportState: SyncTransportState
    let canControlTransport: Bool
    let canOfferCloudAdoption: Bool
    let syncNow: () -> Void
    let pause: () -> Void
    let resume: () -> Void
    let offerCloudAdoption: () -> Void

    var body: some View {
        Menu {
            Text(SyncStatusPresentation.title(for: status))
            if let detail = SyncStatusPresentation.detail(for: status) { Text(detail) }
            if status.pendingMutationCount > 0 { Text("\(status.pendingMutationCount) changes waiting to sync") }
            if status.availability == .available, let summary = status.activeDeviceSummary {
                Text(SyncDeviceSummaryPresentation.title(for: summary))
                if SyncDeviceSummaryPresentation.shouldShowMacUpgradeGuidance(for: summary) {
                    Text(SyncDeviceSummaryPresentation.macUpgradeGuidance())
                }
            }
            if status.availability == .available || canControlTransport {
                Divider()
                if canControlTransport, transportState == .paused {
                    Button("Resume Sync", systemImage: "play.fill", action: resume)
                } else {
                    if status.availability == .available {
                        Button("Sync Now", systemImage: "arrow.triangle.2.circlepath", action: syncNow)
                    }
                    if canControlTransport {
                        Button("Pause Sync", systemImage: "pause.fill", action: pause)
                    }
                }
            }
            if canOfferCloudAdoption {
                Divider()
                Button("Use iCloud…", systemImage: "icloud") {
                    offerCloudAdoption()
                }
            }
        } label: {
            Image(systemName: SyncStatusPresentation.symbol(for: status))
                .accessibilityLabel(SyncStatusPresentation.title(for: status))
                .accessibilityValue(
                    transportState == .paused
                        ? String(localized: "Sync is paused")
                        : SyncStatusPresentation.title(for: status)
                )
        }
    }
}

enum SyncDeviceSummaryPresentation {
    static func shouldShowMacUpgradeGuidance(for summary: SyncDeviceSummary) -> Bool {
        summary.currentPlatform != .mac && summary.otherMacCount == 0
    }

    static func macUpgradeGuidance(locale: Locale = .current) -> String {
        String(
            localized: "To see existing Mac notes here, update Tildone on your Mac to version 2.0 or later. Both devices must use the same iCloud account.",
            locale: locale
        )
    }

    static func title(
        for summary: SyncDeviceSummary,
        locale: Locale = .current
    ) -> String {
        let otherDevices = [
            platformCount(summary.otherIPhoneCount, platform: .iPhone, locale: locale),
            platformCount(summary.otherIPadCount, platform: .iPad, locale: locale),
            platformCount(summary.otherMacCount, platform: .mac, locale: locale)
        ].compactMap { $0 }

        let devices = [currentDevice(summary.currentPlatform, locale: locale)] + otherDevices
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: devices) ?? devices.joined(separator: ", ")
    }

    private static func currentDevice(
        _ platform: SyncClientPlatform,
        locale: Locale
    ) -> String {
        switch platform {
        case .iPhone: String(localized: "This iPhone", locale: locale)
        case .iPad: String(localized: "This iPad", locale: locale)
        case .mac: String(localized: "This Mac", locale: locale)
        }
    }

    private static func platformCount(
        _ count: Int,
        platform: SyncClientPlatform,
        locale: Locale
    ) -> String? {
        guard count > 0 else { return nil }
        return switch platform {
        case .iPhone: String(localized: "\(count) iPhones", locale: locale)
        case .iPad: String(localized: "\(count) iPads", locale: locale)
        case .mac: String(localized: "\(count) Macs", locale: locale)
        }
    }
}
