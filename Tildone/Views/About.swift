//
//  About.swift
//  Tildone
//
//  Created by Diego Rivera on 13/1/24.
//

import SwiftUI

struct About: View {
    
    private var appIconImage: Image? = {
        guard let image = NSImage(named: Id.appIcon) else {
            return nil
        }
        return Image(nsImage: image)
    }()

    private var appVersionLabel: Text? = {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return Text("\(Copy.aboutAppVersion) \(version)")
    }()
    
    var body: some View {
        VStack {
            if appIconImage != nil {
                appIconImage!
                    .resizable()
                    .frame(maxWidth: Frame.aboutIconSize, maxHeight: Frame.aboutIconSize)
            }
            Text(Copy.appName)
                .font(.title)
                .bold()
                .padding(.bottom, 10)
            if appVersionLabel != nil {
                appVersionLabel
                    .font(.subheadline)
                    .padding(.bottom, 10)
            }
            Text(Copy.contentRights)
            if let website = URL(string: Copy.websiteLink) {
                Link(Copy.websiteName, destination: website)
            }
        }
        .padding()
        .frame(width: Frame.aboutWindowWidth, height: Frame.aboutWindowHeight)
    }
}
