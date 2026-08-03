//
//  About.swift
//  Tildone
//
//  Created by Diego Rivera on 13/1/24.
//

import SwiftUI

struct About: View {
    private var appVersionLabel: Text? = {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return Text("Version \(version)")
    }()
    
    var body: some View {
        VStack {
            // This is the compiled Icon Composer app icon, rather than the
            // template status-bar asset. AppKit provides its default bundled
            // representation for use outside the Dock.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: Frame.aboutIconSize, height: Frame.aboutIconSize)
            Text("Tildone")
                .font(.title)
                .bold()
                .padding(.bottom, 10)
            if appVersionLabel != nil {
                appVersionLabel
                    .font(.subheadline)
                    .padding(.bottom, 10)
            }
            Text("© 2023 Diego Rivera")
            if let website = URL(string: "http://cuatro.studio") {
                Link("cuatro.studio", destination: website)
            }
        }
        .padding()
        .frame(width: Frame.aboutWindowWidth, height: Frame.aboutWindowHeight)
    }
}
