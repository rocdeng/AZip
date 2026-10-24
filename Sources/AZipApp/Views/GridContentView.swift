import AZipCore
import SwiftUI

struct GridContentView: View {
    let entries: [VolumeEntry]
    let onOpen: (VolumeEntry) -> Void

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(entries) { entry in
                    FileTile(entry: entry) {
                        onOpen(entry)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
