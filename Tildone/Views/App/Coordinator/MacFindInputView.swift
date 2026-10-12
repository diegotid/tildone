import SwiftUI

struct MacFindInputView: View {
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Find in Notes")
                .font(.headline)
            MacFindSearchField(query: $query)
                .frame(height: 24)
                .onChange(of: query) { _, newQuery in
                    NotificationCenter.default.post(
                        name: .findQueryChanged,
                        object: newQuery.count >= 3 ? newQuery : ""
                    )
                }
            Text("Enter at least 3 characters to start searching notes and tasks.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }
}
