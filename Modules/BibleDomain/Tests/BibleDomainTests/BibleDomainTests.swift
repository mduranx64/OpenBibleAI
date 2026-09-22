import Testing
import BibleDomain

@Test func bibleReferenceStoresItsLocation() {
    let ref = BibleReference(bookID: "GEN", chapter: 1, verse: 1)
    
    #expect(ref.bookID == "GEN")
    #expect(ref.verse == 1)
    #expect(ref.chapter == 1)
}
