//
//  Updates.swift
//  Tildone
//
//  Created by Diego Rivera on 13/1/24.
//

import SwiftUI

struct Updates: View {
    @State private var latestVersion: String?
    @State private var isChecking: Bool = true
    @State private var isVisitingApp: Bool = false
    
    private var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    private var appIconImage: Image? = {
        guard let image = NSImage(named: Id.appIcon) else {
            return nil
        }
        return Image(nsImage: image)
    }()
    
    var body: some View {
        HStack {
            if appIconImage != nil {
                appIconImage!
                    .resizable()
                    .frame(maxWidth: Frame.aboutIconSize, maxHeight: Frame.aboutIconSize)
                    .padding(.leading, 12)
            }
            VStack {
                if isChecking {
                    ProgressView()
                } else {
                    Text(Copy.appName)
                        .font(.title)
                        .bold()
                        .padding(.bottom, 10)
                    if let latest = latestVersion,
                       let current = currentVersion,
                       latest.compare(current, options: .numeric) == .orderedDescending
                    {
                        Text(Copy.appVersionAvailable)
                        HStack(spacing: 2) {
                            Text("\(Copy.aboutAppVersion) \(latest)")
                                .font(.subheadline)
                            if currentVersion != nil {
                                Text("(\(Copy.aboutCurrentVersion) \(currentVersion!))")
                                    .font(.subheadline)
                            }
                        }
                        if let appStoreLink = URL(string: UpdateChecker.Remote.appStoreAppUrl) {
                            Button(Copy.appVersionVisiteStore) {
                                NSWorkspace.shared.open(appStoreLink)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.accentColor)
                            .padding(.top, 12)
                        } else {
                            Text(Copy.appVersionVisiteStore)
                        }
                    } else {
                        Text(Copy.appVersionUpToDate)
                        if let current = currentVersion {
                            Text("\(Copy.aboutAppVersion) \(current)")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .onAppear {
                UpdateChecker.getAppStoreVersion { version in
                    self.latestVersion = version
                    self.isChecking = false
                }
            }
        }
        .frame(width: 360, height: 180)
    }
}
