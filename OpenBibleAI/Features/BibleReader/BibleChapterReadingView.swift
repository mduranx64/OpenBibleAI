import SwiftUI
import BibleDomain

struct BibleChapterReadingView: View {
    /// Location heading, e.g. "John 3".
    let title: String
    let verses: [BibleVerse]
    let selectedReference: BibleReference?
    let selectionRevision: Int
    let selectVerse: (BibleReference) -> Void

    // Scroll position is separate from selection: manual scrolling must not
    // change the verse being studied. A new selection requests a scroll.
    @State private var visibleReference: BibleReference?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title.bold())
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("chapterTitle")

                ForEach(verses, id: \.reference) { verse in
                    Button {
                        selectVerse(verse.reference)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(verse.reference.verse)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 24, alignment: .trailing)
                            Text(verse.text)
                                .font(.title3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(
                            selectedReference == verse.reference
                                ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedReference == verse.reference ? .isSelected : [])
                    .accessibilityIdentifier("verse-\(verse.reference.bookID)-\(verse.reference.chapter)-\(verse.reference.verse)")
                    .id(verse.reference)
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: 720, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition(id: $visibleReference, anchor: .center)
        .onChange(of: selectionRevision, initial: true) { _, _ in
            guard let selectedReference,
                  verses.contains(where: { $0.reference == selectedReference }) else { return }
            visibleReference = selectedReference
        }
    }
}
