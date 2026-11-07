import XCTest
import SwiftData
@testable import NotoNotes

final class NotebookTests: XCTestCase {
    func testCivilDaysAcrossClockAndYearChanges() {
        for zone in ["America/Los_Angeles","Pacific/Auckland","Europe/Berlin"] {
            let tz = TimeZone(identifier:zone)!
            for (end,expected) in [(20240311,20240310),(20241104,20241103),(20240301,20240229),(20250101,20241231)] {
                XCTAssertEqual(Days.ago(1,from:Days.date(end,zone:tz),zone:tz),expected)
                XCTAssertEqual(Days.key(Days.date(expected,zone:tz),zone:tz),expected)
            }
        }
    }
    @MainActor func testDraftPersistenceMetadataAndRestoration() throws {
        let container = try ModelContainer(for:Note.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let ctx = container.mainContext
        let n = Note()
        let created = n.createdAt
        ctx.insert(n)
        let draft = Draft(title:"Notebook",body:"یادداشت and notes",day:Days.ago(10))
        try draft.save(n,in:ctx)
        let fresh = ModelContext(container)
        let stored = try XCTUnwrap(fresh.fetch(FetchDescriptor<Note>()).first)
        XCTAssertEqual(Draft.load(stored),draft)
        XCTAssertEqual(stored.createdAt,created)
        XCTAssertTrue(stored.matches("یادداشت"))
        XCTAssertTrue(stored.matches("book"))
        stored.deletedAt = .now
        try fresh.save()
        stored.deletedAt = nil
        try fresh.save()
        XCTAssertNil(stored.deletedAt)
        XCTAssertEqual(draft.day,stored.noteDate)
    }
    func testUnicodeAnchorAndStaleReview() throws {
        let id = UUID(), s = "سلام 🙂 teh"
        let edit = Suggestion(id:UUID(),original:"teh",replacement:"the",category:"spelling",explanation:"Spelling",start:(s as NSString).range(of:"teh").location,length:3)
        let r = Review(noteID:id,version:2,passage:NSRange(location:0,length:s.utf16.count),source:s,edits:[edit])
        XCTAssertEqual(try r.ranges(in:s,note:id,revision:2).count,1)
        XCTAssertThrowsError(try r.ranges(in:s,note:id,revision:3))
        XCTAssertThrowsError(try r.ranges(in:s,note:UUID(),revision:2))
        XCTAssertThrowsError(try r.ranges(in:"changed",note:id,revision:2))
    }
    @MainActor func testPopulatedSearch() {
        let notes = (1...3000).map { Note(title:"Entry \($0)",content:"A line from my notebook") }
        measure { XCTAssertEqual(notes.filter{$0.matches("Entry 3000")}.count,1) }
    }
    func testConsentPreventsNetwork() async {
        UserDefaults.standard.set(false,forKey:"cloud")
        do { _ = try await Writing.analyze("private",action:"Rewrite",tone:nil,language:"en"); XCTFail() }
        catch { XCTAssertEqual(error.localizedDescription,WritingError.consent.localizedDescription) }
    }
}
