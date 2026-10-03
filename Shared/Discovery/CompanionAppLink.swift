import Foundation

enum CompanionAppLink {
    static let writeReview = appStore.appending(queryItems: [URLQueryItem(name: "action", value: "write-review")])

    // One App Store record contains the native Mac and iPhone apps.
    static let appStore = URL(string: "https://apps.apple.com/app/id6473126292")!
}
