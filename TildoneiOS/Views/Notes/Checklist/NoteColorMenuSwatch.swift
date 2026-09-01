import UIKit
import SwiftUI
import TildoneDomain

enum NoteColorMenuSwatch {
    static func image(for color: NoteColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 14, height: 14))
        return renderer.image { context in
            let circle = CGRect(x: 1, y: 1, width: 12, height: 12)
            context.cgContext.setFillColor(UIColor(color.swiftUIColor).cgColor)
            context.cgContext.fillEllipse(in: circle)
            context.cgContext.setStrokeColor(UIColor.black.withAlphaComponent(0.18).cgColor)
            context.cgContext.setLineWidth(1)
            context.cgContext.strokeEllipse(in: circle.insetBy(dx: 0.5, dy: 0.5))
        }
        .withRenderingMode(.alwaysOriginal)
    }
}
