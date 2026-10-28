import SwiftUI
import CoreImage.CIFilterBuiltins

struct CompanionDownloadQRCode: View {
    var size: CGFloat = 72

    static let image: CGImage? = {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(CompanionAppLink.appStore.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let enlarged = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return CIContext().createCGImage(enlarged, from: enlarged.extent)
    }()

    var body: some View {
        if let image = Self.image {
            Image(decorative: image, scale: 1)
                .interpolation(.none).resizable()
                .frame(width: size, height: size)
                .padding(size / 9)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true) // The Copy Link action provides an accessible alternative.
        }
    }
}
