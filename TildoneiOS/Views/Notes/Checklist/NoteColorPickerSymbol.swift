import SwiftUI
import TildoneDomain

struct NoteColorPickerSymbol: View {
    let color: NoteColor

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                        center: .center
                    ),
                    lineWidth: 2.5
                )
            Circle()
                .fill(color.swiftUIColor)
                .padding(5)
                .overlay {
                    Circle()
                        .stroke(.black.opacity(0.18), lineWidth: 0.5)
                        .padding(5)
                }
        }
        .frame(width: 24, height: 24)
    }
}
