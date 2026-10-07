//
//  KishoTests.swift
//  KishoTests
//
//  Created by Peter Macdonald on 30/05/2025.
//

import XCTest
import Combine
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import PDFKit
import RichTextEditor
@testable import Kisho

final class KishoTests: XCTestCase {
    
    private func makeSection(title: String, body: String, children: [KishoSection] = []) -> KishoSection {
        let model = RichTextModel()
        model.attributedString = NSAttributedString(string: body)
        return KishoSection(title: title, content: model, children: children)
    }
    
    func testFullSaveOpenCycleShowsAllSections() throws {
        let childA = makeSection(title: "Alpha", body: "AAA body")
        let childB = makeSection(title: "Bravo", body: "BBB body")
        let childC = makeSection(title: "Charlie", body: "CCC body")
        let root = makeSection(title: "Root", body: "ROOT body", children: [childA, childB, childC])
        
        let model = KishoDocumentModel(sections: [root])
        model.selectedSectionID = root.id
        
        // Encode like KishoDocument save
        let data = try JSONEncoder().encode(model)
        // Decode like KishoDocument open
        let reopened = try JSONDecoder().decode(KishoDocumentModel.self, from: data)
        
        guard let selected = reopened.selectedSection else {
            return XCTFail("no selected section after reopen")
        }
        
        XCTAssertEqual(selected.children.count, 3, "children lost on reopen")
        let bodies = selected.subtree.map { $0.content.attributedString.string }
        XCTAssertEqual(bodies, ["ROOT body", "AAA body", "BBB body", "CCC body"])
        XCTAssertEqual(selected.children.map { $0.title }, ["Alpha", "Bravo", "Charlie"])
    }
    
    func testMakeChildrenSplitsBodyParagraphs() throws {
        let root = makeSection(title: "Root", body: "First paragraph.\n\nSecond paragraph.")
        let document = KishoDocumentModel(sections: [root])
        document.selectedSectionID = root.id
        
        document.makeChildren()
        
        XCTAssertEqual(root.content.attributedString.string, "")
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(root.children[0].title, "First paragraph.")
        XCTAssertEqual(root.children[1].title, "Second paragraph.")
        // The paragraph itself becomes the new section's body.
        XCTAssertEqual(root.children[0].content.attributedString.string, "First paragraph.")
        XCTAssertEqual(root.children[1].content.attributedString.string, "Second paragraph.")
        XCTAssertEqual(document.selectedSectionID, root.children[0].id)
        XCTAssertTrue(root.children.allSatisfy { $0.parent === root })
    }
    
    func testMakeChildrenSplitsExtraTitleLines() throws {
        let root = makeSection(title: "Root\nAlpha paragraph\nBravo paragraph", body: "")
        let document = KishoDocumentModel(sections: [root])
        document.selectedSectionID = root.id
        
        document.makeChildren()
        
        XCTAssertEqual(root.title, "Root")
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(root.children[0].title, "Alpha paragraph")
        XCTAssertEqual(root.children[1].title, "Bravo paragraph")
        XCTAssertEqual(root.children[0].content.attributedString.string, "Alpha paragraph")
        XCTAssertEqual(root.children[1].content.attributedString.string, "Bravo paragraph")
    }
    
    func testMakeChildrenSplitsSingleNewlines() throws {
        let root = makeSection(title: "Root", body: "First paragraph.\nSecond paragraph.\nThird paragraph.")
        let document = KishoDocumentModel(sections: [root])
        document.selectedSectionID = root.id
        
        document.makeChildren()
        
        XCTAssertEqual(root.children.count, 3, "each line should become its own section")
        XCTAssertEqual(root.children[0].title, "First paragraph.")
        XCTAssertEqual(root.children[1].title, "Second paragraph.")
        XCTAssertEqual(root.children[2].title, "Third paragraph.")
    }
    
    func testSplitParagraphsHandlesLineSeparators() throws {
        let source = NSAttributedString(string: "One\u{2028}Two\u{2029}Three")
        let parts = KishoSection.splitParagraphs(from: source)
        XCTAssertEqual(parts.map { $0.attributedString.string }, ["One", "Two", "Three"])
    }
    
    func testMakeChildrenOnEmptySectionDoesNothing() throws {
        let root = makeSection(title: "Root", body: "")
        let document = KishoDocumentModel(sections: [root])
        document.selectedSectionID = root.id
        
        document.makeChildren()
        
        XCTAssertEqual(root.children.count, 0)
        XCTAssertEqual(document.selectedSectionID, root.id)
    }
    
    // MARK: - Tree operations
    
    private func makeDocument() -> (KishoDocumentModel, KishoSection, KishoSection, KishoSection, KishoSection) {
        // A
        //   A1
        //   A2
        // B
        let a1 = makeSection(title: "A1", body: "a1")
        let a2 = makeSection(title: "A2", body: "a2")
        let a = makeSection(title: "A", body: "a", children: [a1, a2])
        let b = makeSection(title: "B", body: "b")
        let document = KishoDocumentModel(sections: [a, b])
        return (document, a, a1, a2, b)
    }
    
    private func titles(_ document: KishoDocumentModel) -> [String] {
        document.orderedSections.map { $0.title }
    }
    
    func testSplitTitleUsesFirstSentenceAndKeepsFormatting() throws {
        let body = NSMutableAttributedString(string: "Short one. And the rest of it.")
        body.addAttribute(.font, value: PlatformFont.boldSystemFont(ofSize: 14), range: NSRange(location: 0, length: 5))
        let model = RichTextModel()
        model.attributedString = body
        let root = KishoSection(title: "Root", content: model)
        let document = KishoDocumentModel(sections: [root])
        
        document.makeChildren()
        
        XCTAssertEqual(root.children.count, 1)
        XCTAssertEqual(root.children[0].title, "Short one.")
        XCTAssertEqual(root.children[0].content.attributedString.string, "Short one. And the rest of it.")
        let font = root.children[0].content.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        XCTAssertTrue(font?.isBoldTrait ?? false, "formatting must survive a split")
    }
    
    func testSplitInsertsParagraphsBeforeExistingChildren() throws {
        let existing = makeSection(title: "Existing child", body: "x")
        let root = makeSection(title: "Root", body: "P1\nP2", children: [existing])
        let document = KishoDocumentModel(sections: [root])
        
        document.makeChildren()
        
        XCTAssertEqual(root.children.map { $0.title }, ["P1", "P2", "Existing child"])
    }
    
    func testSplitThenGatherRoundTripsText() throws {
        let root = makeSection(title: "Root", body: "First paragraph.\nSecond paragraph.")
        let document = KishoDocumentModel(sections: [root])
        
        document.makeChildren()
        document.selectedSectionID = root.id
        document.gather()
        
        XCTAssertTrue(root.children.isEmpty)
        XCTAssertEqual(root.content.attributedString.string, "First paragraph.\nSecond paragraph.")
    }
    
    func testGatherIncludesGrandchildrenInReadingOrder() throws {
        let grandchild = makeSection(title: "GC", body: "gc")
        let child = makeSection(title: "C", body: "c", children: [grandchild])
        let root = makeSection(title: "Root", body: "r", children: [child])
        let document = KishoDocumentModel(sections: [root])
        
        document.gather()
        
        XCTAssertEqual(root.content.attributedString.string, "r\nc\ngc")
    }
    
    func testAddSiblingInsertsDirectlyAfterSelection() throws {
        let (document, a, a1, _, _) = makeDocument()
        document.selectedSectionID = a1.id
        
        document.addSiblingSection()
        
        XCTAssertEqual(a.children.count, 3)
        XCTAssertEqual(a.children[1].id, document.selectedSectionID)
        XCTAssertTrue(a.children[1].parent === a)
    }
    
    func testAddSiblingAtTopLevelInsertsAfterSelection() throws {
        let (document, a, _, _, b) = makeDocument()
        document.selectedSectionID = a.id
        
        document.addSiblingSection()
        
        XCTAssertEqual(document.sections.count, 3)
        XCTAssertEqual(document.sections[1].id, document.selectedSectionID)
        XCTAssertEqual(document.sections[2].id, b.id)
        XCTAssertNil(document.sections[1].parent)
    }
    
    func testAddChildAppendsToSelection() throws {
        let (document, a, _, a2, _) = makeDocument()
        document.selectedSectionID = a.id
        
        document.addChildSection()
        
        XCTAssertEqual(a.children.count, 3)
        XCTAssertEqual(a.children[2].id, document.selectedSectionID)
        XCTAssertEqual(a.children[1].id, a2.id)
    }
    
    func testDeleteLastTopLevelSectionSelectsRemainingOne() throws {
        let (document, a, _, _, b) = makeDocument()
        document.selectedSectionID = b.id
        
        document.deleteSelectedSection()
        
        XCTAssertEqual(document.sections.map { $0.id }, [a.id])
        XCTAssertEqual(document.selectedSectionID, a.id)
    }
    
    func testDeleteFirstChildSelectsNextSibling() throws {
        let (document, a, a1, a2, _) = makeDocument()
        document.selectedSectionID = a1.id
        
        document.deleteSelectedSection()
        
        XCTAssertEqual(a.children.map { $0.id }, [a2.id])
        XCTAssertEqual(document.selectedSectionID, a2.id)
    }
    
    func testDeleteOnlyChildSelectsParent() throws {
        let only = makeSection(title: "Only", body: "")
        let root = makeSection(title: "Root", body: "", children: [only])
        let document = KishoDocumentModel(sections: [root])
        document.selectedSectionID = only.id
        
        document.deleteSelectedSection()
        
        XCTAssertEqual(document.selectedSectionID, root.id)
    }
    
    func testMoveToTopLevelDoesNotLoseSection() throws {
        let (document, a, a1, a2, b) = makeDocument()
        
        document.move(sectionID: a1.id, to: .before(b.id))
        
        XCTAssertEqual(document.sections.map { $0.id }, [a.id, a1.id, b.id])
        XCTAssertEqual(a.children.map { $0.id }, [a2.id])
        XCTAssertNil(a1.parent)
        XCTAssertEqual(document.orderedSections.count, 4, "no section may vanish in a move")
    }
    
    func testMoveAfterLastTopLevelSection() throws {
        let (document, a, a1, _, b) = makeDocument()
        
        document.move(sectionID: a1.id, to: .after(b.id))
        
        XCTAssertEqual(document.sections.map { $0.id }, [a.id, b.id, a1.id])
    }
    
    func testMoveIntoOwnDescendantIsIgnored() throws {
        let (document, a, a1, _, _) = makeDocument()
        let before = titles(document)
        
        document.move(sectionID: a.id, to: .into(a1.id))
        document.move(sectionID: a.id, to: .before(a1.id))
        document.move(sectionID: a.id, to: .after(a1.id))
        document.move(sectionID: a.id, to: .into(a.id))
        
        XCTAssertEqual(titles(document), before, "moving a section into its own subtree must be a no-op")
        XCTAssertEqual(document.orderedSections.count, 4)
    }
    
    func testMoveIntoSectionAppendsAsLastChildAndUpdatesParent() throws {
        let (document, a, _, _, b) = makeDocument()
        
        document.move(sectionID: b.id, to: .into(a.id))
        
        XCTAssertEqual(document.sections.map { $0.id }, [a.id])
        XCTAssertEqual(a.children.last?.id, b.id)
        XCTAssertTrue(b.parent === a)
        XCTAssertEqual(document.selectedSectionID, b.id)
    }
    
    func testMoveWithinSameParentDownwards() throws {
        let (document, a, a1, a2, _) = makeDocument()
        
        document.move(sectionID: a1.id, to: .after(a2.id))
        
        XCTAssertEqual(a.children.map { $0.id }, [a2.id, a1.id])
    }
    
    func testMoveUndoRestoresOriginalPlace() throws {
        let (document, a, a1, a2, b) = makeDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        
        undo.beginUndoGrouping()
        document.move(sectionID: a1.id, to: .into(b.id), using: undo)
        undo.endUndoGrouping()
        XCTAssertEqual(b.children.map { $0.id }, [a1.id])
        
        undo.undo()
        XCTAssertEqual(a.children.map { $0.id }, [a1.id, a2.id])
        XCTAssertTrue(b.children.isEmpty)
        XCTAssertTrue(a1.parent === a)
        
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertEqual(b.children.map { $0.id }, [a1.id])
        XCTAssertEqual(a.children.map { $0.id }, [a2.id])
    }
    
    func testDeleteUndoRedoAreSymmetric() throws {
        let (document, a, a1, a2, _) = makeDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        document.selectedSectionID = a1.id
        
        undo.beginUndoGrouping()
        document.deleteSelectedSection(using: undo)
        undo.endUndoGrouping()
        XCTAssertEqual(a.children.map { $0.id }, [a2.id])
        
        undo.undo()
        XCTAssertEqual(a.children.map { $0.id }, [a1.id, a2.id])
        XCTAssertEqual(document.selectedSectionID, a1.id)
        
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertEqual(a.children.map { $0.id }, [a2.id])
        
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(a.children.map { $0.id }, [a1.id, a2.id])
    }
    
    func testSplitUndoRestoresEverything() throws {
        let root = makeSection(title: "Root", body: "P1\nP2")
        let document = KishoDocumentModel(sections: [root])
        let undo = UndoManager()
        undo.groupsByEvent = false
        
        undo.beginUndoGrouping()
        document.makeChildren(undoManager: undo)
        undo.endUndoGrouping()
        XCTAssertEqual(root.children.count, 2)
        
        undo.undo()
        XCTAssertTrue(root.children.isEmpty)
        XCTAssertEqual(root.content.attributedString.string, "P1\nP2")
        XCTAssertEqual(document.selectedSectionID, root.id)
        
        undo.redo()
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(root.content.attributedString.string, "")
    }
    
    func testStructureHooksFireOncePerOperation() throws {
        let (document, _, a1, _, b) = makeDocument()
        var before = 0
        var after = 0
        document.beforeStructureEdit = { before += 1 }
        document.afterStructureEdit = { after += 1 }
        
        document.move(sectionID: a1.id, to: .into(b.id))
        XCTAssertEqual(before, 1)
        XCTAssertEqual(after, 1)
        
        before = 0; after = 0
        b.content.attributedString = NSAttributedString(string: "P1\nP2")
        document.selectedSectionID = b.id
        document.makeChildren()
        XCTAssertEqual(before, 1, "split must flush the editor exactly once")
        XCTAssertEqual(after, 1)
        
        before = 0; after = 0
        document.selectedSectionID = b.id
        document.gather()
        XCTAssertEqual(before, 1)
        XCTAssertEqual(after, 1)
    }
    
    func testNextAndPreviousFollowReadingOrder() throws {
        let (document, a, a1, a2, b) = makeDocument()
        document.selectedSectionID = a.id
        
        document.selectNext()
        XCTAssertEqual(document.selectedSectionID, a1.id)
        document.selectNext()
        XCTAssertEqual(document.selectedSectionID, a2.id)
        document.selectNext()
        XCTAssertEqual(document.selectedSectionID, b.id)
        document.selectNext()
        XCTAssertEqual(document.selectedSectionID, b.id, "stays on the last section")
        
        document.selectPrevious()
        XCTAssertEqual(document.selectedSectionID, a2.id)
        document.selectUp()
        XCTAssertEqual(document.selectedSectionID, a.id)
        document.selectDown()
        XCTAssertEqual(document.selectedSectionID, a1.id)
    }
    
    func testLevelUpWorksAfterMove() throws {
        let (document, _, a1, _, b) = makeDocument()
        document.move(sectionID: a1.id, to: .into(b.id))
        document.selectedSectionID = a1.id
        
        document.selectUp()
        
        XCTAssertEqual(document.selectedSectionID, b.id)
    }
    
    func testDocumentWithNoSelectionCanBeReopened() throws {
        let root = makeSection(title: "Root", body: "body")
        let document = KishoDocumentModel(sections: [root])
        document.selectedSectionID = nil
        
        let data = try JSONEncoder().encode(document)
        let reopened = try JSONDecoder().decode(KishoDocumentModel.self, from: data)
        
        XCTAssertEqual(reopened.sections.count, 1)
        XCTAssertEqual(reopened.selectedSectionID, reopened.sections.first?.id, "falls back to the first section")
    }
    
    func testReopenedDocumentHasParentPointers() throws {
        let (document, _, _, _, _) = makeDocument()
        let data = try JSONEncoder().encode(document)
        let reopened = try JSONDecoder().decode(KishoDocumentModel.self, from: data)
        
        let a = reopened.sections[0]
        XCTAssertNil(a.parent)
        XCTAssertTrue(a.children.allSatisfy { $0.parent === a })
    }
    
    func testSetTagsRegistersUndo() throws {
        let (document, a, _, _, _) = makeDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        
        undo.beginUndoGrouping()
        document.setTags([" draft ", "", "idea"], for: a, using: undo)
        undo.endUndoGrouping()
        XCTAssertEqual(a.tags, ["draft", "idea"])
        XCTAssertTrue(undo.canUndo)
        
        undo.undo()
        XCTAssertEqual(a.tags, [])
    }
    
    func testTypographyUndoRestoresFonts() throws {
        let root = makeSection(title: "Root", body: "Hello")
        let document = KishoDocumentModel(sections: [root])
        let undo = UndoManager()
        undo.groupsByEvent = false
        var settings = document.typography
        settings.fontSize = 30
        
        undo.beginUndoGrouping()
        document.setTypography(settings, undoManager: undo)
        undo.endUndoGrouping()
        let big = root.content.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        XCTAssertEqual(big?.pointSize, 30)
        
        undo.undo()
        let restored = root.content.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        XCTAssertNotEqual(restored?.pointSize, 30)
        XCTAssertEqual(document.typography.fontSize, TypographySettings.defaultFontSize, "undo restores the previous settings too")
    }
    
    func testExportedAttributedTextIsBlack() throws {
        let root = makeSection(title: "Root", body: "Hello")
        root.content.applyTypography(font: PlatformFont.systemFont(ofSize: 12), color: PlatformColor.label)
        let exported = Exporter.attributedText(from: [root])
        var allBlack = true
        exported.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: exported.length)) { value, _, _ in
            if (value as? PlatformColor) != PlatformColor.black { allBlack = false }
        }
        XCTAssertTrue(allBlack, "export must not carry the appearance-adaptive label colour")
    }
    
    // MARK: - Card editor model support
    
    /// Undo manager with manual grouping: the model opens one group per new
    /// typing burst, so coalesced keystrokes add nothing and separate bursts
    /// are separate steps — without needing a run loop.
    private func manualUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }
    
    func testSetTitleIsUndoableAndTrims() throws {
        let (document, a, _, _, _) = makeDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        
        undo.beginUndoGrouping()
        document.setTitle("  Chapter One  ", for: a, using: undo)
        undo.endUndoGrouping()
        XCTAssertEqual(a.title, "Chapter One")
        
        undo.undo()
        XCTAssertEqual(a.title, "A")
        undo.redo()
        XCTAssertEqual(a.title, "Chapter One")
    }
    
    func testBodyEditsCoalesceIntoOneUndoStep() throws {
        let (document, a, _, _, _) = makeDocument()
        let undo = manualUndoManager()
        
        // Simulate the editor applying three quick keystrokes.
        let steps = ["ab", "abc", "abcd"].map { NSAttributedString(string: $0) }
        var previous = a.content.attributedString
        var location = 1
        for step in steps {
            a.content.attributedString = step
            document.recordBodyEdit(for: a, from: previous, to: step, editLocation: location, using: undo)
            previous = step
            location += 1
        }
        XCTAssertEqual(a.content.attributedString.string, "abcd")
        
        undo.undo()
        XCTAssertEqual(a.content.attributedString.string, "a", "one undo takes back the whole burst")
        XCTAssertFalse(undo.canUndo, "the burst registered a single undo step")
        
        undo.redo()
        XCTAssertEqual(a.content.attributedString.string, "abcd")
    }
    
    func testSidebarSelectionRequestsBodyFocusButEditorClickDoesNot() throws {
        let (document, a, a1, _, _) = makeDocument()
        document.focusRequest = nil
        
        document.select(section: a1)
        XCTAssertEqual(document.selectedSectionID, a1.id)
        XCTAssertEqual(document.focusRequest?.sectionID, a1.id)
        XCTAssertEqual(document.focusRequest?.field, .body)
        
        // The editor sets the selection directly when the caret moves.
        document.focusRequest = nil
        document.selectedSectionID = a.id
        XCTAssertNil(document.focusRequest)
    }
    
    func testAddSectionRequestsTitleFocus() throws {
        let (document, a, _, _, _) = makeDocument()
        document.newBlockFocus = { .title }   // independent of the Mac's Settings
        document.selectedSectionID = a.id
        document.addSiblingSection()
        XCTAssertEqual(document.focusRequest?.sectionID, document.selectedSectionID)
        XCTAssertEqual(document.focusRequest?.field, .title)
    }
    
    func testRetypesetPreservesBoldAndItalicPerRun() throws {
        let text = NSMutableAttributedString(string: "plain bold italic")
        let base = PlatformFont.systemFont(ofSize: 12)
        text.addAttribute(.font, value: base, range: NSRange(location: 0, length: 17))
        text.addAttribute(.font, value: base.addingTraits(bold: true, italic: false), range: NSRange(location: 6, length: 4))
        text.addAttribute(.font, value: base.addingTraits(bold: false, italic: true), range: NSRange(location: 11, length: 6))
        
        let newBase = PlatformFont(name: "Helvetica", size: 16) ?? PlatformFont.systemFont(ofSize: 16)
        let result = KishoSection.retypeset(text, base: newBase, color: nil)
        
        func font(at i: Int) -> PlatformFont { result.attribute(.font, at: i, effectiveRange: nil) as! PlatformFont }
        XCTAssertEqual(font(at: 0).pointSize, 16)
        XCTAssertFalse(font(at: 0).isBoldTrait)
        XCTAssertTrue(font(at: 7).isBoldTrait, "bold run must stay bold")
        XCTAssertEqual(font(at: 7).pointSize, 16)
        XCTAssertTrue(font(at: 12).isItalicTrait, "italic run must stay italic")
    }
    
    func testDocumentTotalWordCount() throws {
        let (document, a, _, _, _) = makeDocument()
        XCTAssertEqual(document.totalWordCount, 4)
        a.content.attributedString = NSAttributedString(string: "one two three")
        XCTAssertEqual(document.totalWordCount, 6, "count follows content changes despite caching")
    }
    
    // MARK: - Phase 1: undo bursts, caret, ancestor refresh
    
    func testBurstEndsOnParagraphBreak() throws {
        let (document, a, _, _, _) = makeDocument()   // a's body is "a"
        let undo = manualUndoManager()
        func edit(_ text: String, at loc: Int) {
            let old = a.content.attributedString
            a.content.attributedString = NSAttributedString(string: text)
            document.recordBodyEdit(for: a, from: old, to: a.content.attributedString, editLocation: loc, using: undo)
        }
        edit("ab", at: 1)
        edit("ab\n", at: 2)      // Return ends the burst
        edit("ab\nc", at: 3)
        edit("ab\ncd", at: 4)
        
        undo.undo()
        XCTAssertEqual(a.content.attributedString.string, "ab\n", "second line is its own undo step")
        undo.undo()
        XCTAssertEqual(a.content.attributedString.string, "a")
    }
    
    func testBurstEndsOnCaretJump() throws {
        let (document, a, _, _, _) = makeDocument()
        a.content.attributedString = NSAttributedString(string: "hello world")
        let undo = manualUndoManager()
        func edit(_ text: String, at loc: Int) {
            let old = a.content.attributedString
            a.content.attributedString = NSAttributedString(string: text)
            document.recordBodyEdit(for: a, from: old, to: a.content.attributedString, editLocation: loc, using: undo)
        }
        edit("hello world!", at: 11)
        edit("hello world!!", at: 12)
        edit("Xhello world!!", at: 0)   // jumped to the start
        
        undo.undo()
        XCTAssertEqual(a.content.attributedString.string, "hello world!!", "edit after a caret jump is a separate step")
        undo.undo()
        XCTAssertEqual(a.content.attributedString.string, "hello world")
    }
    
    func testUndoRequestsCaretAtEditSite() throws {
        let (document, a, _, _, _) = makeDocument()
        a.content.attributedString = NSAttributedString(string: "hello world")
        let undo = manualUndoManager()
        let old = a.content.attributedString
        a.content.attributedString = NSAttributedString(string: "hello big world")
        document.recordBodyEdit(for: a, from: old, to: a.content.attributedString, editLocation: 6, using: undo)
        
        undo.undo()
        XCTAssertEqual(document.focusRequest?.sectionID, a.id)
        XCTAssertEqual(document.focusRequest?.field, .body)
        XCTAssertEqual(document.focusRequest?.caret, 6)
        
        undo.redo()
        XCTAssertEqual(a.content.attributedString.string, "hello big world")
        XCTAssertEqual(document.focusRequest?.caret, 10, "redo places the caret after the restored text")
    }
    
    func testBodyEditNotifiesAncestorsAndStats() throws {
        let (document, a, a1, _, _) = makeDocument()
        var parentChanges = 0
        let sub = a.objectWillChange.sink { _ in parentChanges += 1 }
        let statsBefore = document.stats.version
        
        document.recordBodyEdit(for: a1, from: a1.content.attributedString, to: NSAttributedString(string: "new"))
        
        XCTAssertGreaterThan(parentChanges, 0, "parent row must refresh its subtree word count")
        XCTAssertNotEqual(document.stats.version, statsBefore)
        sub.cancel()
    }
    
    func testDefaultTypographyIsAPickableFamily() throws {
        let settings = TypographySettings()
        XCTAssertEqual(settings.fontFamily, "Georgia")
        XCTAssertEqual(settings.fontSize, 14)
        XCTAssertFalse(settings.fontFamily.hasPrefix("."), "default must be a real family, not the system font's internal name")
        XCTAssertTrue(PlatformFont.availableFamilyNames.contains(settings.fontFamily))
        XCTAssertEqual(TypographySettings.displayName(forFamily: ".AppleSystemUIFont"), "System Font")
        XCTAssertEqual(TypographySettings.displayName(forFamily: "Georgia"), "Georgia")
        XCTAssertEqual(KishoDocumentModel().typography, settings)
    }
    
    // MARK: - Phase 2: find & replace, tag filter
    
    func testFindMatchesCoverTitlesBodiesAndTagsInReadingOrder() throws {
        let (document, a, a1, _, b) = makeDocument()
        a.title = "Alpha chapter"
        a.content.attributedString = NSAttributedString(string: "the alpha and the ALPHA")
        a1.tags = ["alpha-draft"]
        b.title = "Beta"
        
        let matches = document.findMatches("alpha")
        XCTAssertEqual(matches.count, 4)
        XCTAssertEqual(matches[0], SearchMatch(sectionID: a.id, field: .title, range: NSRange(location: 0, length: 5)))
        XCTAssertEqual(matches[1].field, .body)
        XCTAssertEqual(matches[1].range, NSRange(location: 4, length: 5))
        XCTAssertEqual(matches[2].range, NSRange(location: 18, length: 5), "case-insensitive by default")
        XCTAssertEqual(matches[3], SearchMatch(sectionID: a1.id, field: .tag(0), range: NSRange(location: 0, length: 5)))
        
        XCTAssertEqual(document.findMatches("alpha", matchCase: true).count, 2,
                       "match case: only the lowercase body hit and the tag; 'Alpha' and 'ALPHA' are excluded")
        XCTAssertTrue(document.findMatches("").isEmpty)
    }
    
    func testReplaceSingleBodyMatchKeepsFormattingAndIsUndoable() throws {
        let (document, a, _, _, _) = makeDocument()
        let body = NSMutableAttributedString(string: "keep the colour")
        body.addAttribute(.font, value: PlatformFont.boldSystemFont(ofSize: 12), range: NSRange(location: 9, length: 6))
        a.content.attributedString = body
        let undo = manualUndoManager()
        
        let match = document.findMatches("colour").first!
        XCTAssertTrue(document.replace(match, with: "color", using: undo))
        XCTAssertEqual(a.content.attributedString.string, "keep the color")
        let font = a.content.attributedString.attribute(.font, at: 9, effectiveRange: nil) as? PlatformFont
        XCTAssertTrue(font!.isBoldTrait, "replacement inherits the run's attributes")
        
        undo.undo()
        XCTAssertEqual(a.content.attributedString.string, "keep the colour")
    }
    
    func testReplaceAllAcrossFieldsIsOneUndoStep() throws {
        let (document, a, a1, a2, b) = makeDocument()
        a.title = "cat title"
        a.content.attributedString = NSAttributedString(string: "cat and cat")
        a1.tags = ["cat"]
        a2.content.attributedString = NSAttributedString(string: "no match here")
        b.title = "Cat"
        let undo = manualUndoManager()
        
        let count = document.replaceAll("cat", with: "dog", using: undo)
        XCTAssertEqual(count, 5)
        XCTAssertEqual(a.title, "dog title")
        XCTAssertEqual(a.content.attributedString.string, "dog and dog")
        XCTAssertEqual(a1.tags, ["dog"])
        XCTAssertEqual(b.title, "Dog", "a capitalised match takes a capitalised replacement")
        XCTAssertTrue(document.findMatches("cat").isEmpty)
        
        undo.undo()
        XCTAssertEqual(a.title, "cat title")
        XCTAssertEqual(a.content.attributedString.string, "cat and cat")
        XCTAssertEqual(a1.tags, ["cat"])
        XCTAssertEqual(b.title, "Cat")
        XCTAssertFalse(undo.canUndo, "replace all is a single undo step")
    }
    
    func testReplacementFollowsCaseOfMatchUnlessMatchingCase() throws {
        typealias M = KishoDocumentModel
        XCTAssertEqual(M.replacement("stream", matchingCaseOf: "river"), "stream")
        XCTAssertEqual(M.replacement("stream", matchingCaseOf: "River"), "Stream")
        XCTAssertEqual(M.replacement("stream", matchingCaseOf: "RIVER"), "STREAM")
        XCTAssertEqual(M.replacement("Stream", matchingCaseOf: "river"), "Stream", "typed capitals are kept")
        XCTAssertEqual(M.replacement("stream", matchingCaseOf: "I"), "Stream", "one capital letter is capitalised, not shouted")
        XCTAssertEqual(M.replacement("stream", matchingCaseOf: "RiVer"), "Stream", "mixed case falls back to capitalising")
        XCTAssertEqual(M.replacement("stream", matchingCaseOf: "123"), "stream")
        
        let (document, a, _, _, _) = makeDocument()
        a.content.attributedString = NSAttributedString(string: "River and RIVER and river")
        XCTAssertEqual(document.replaceAll("river", with: "stream"), 3)
        XCTAssertEqual(a.content.attributedString.string, "Stream and STREAM and stream")
        
        a.content.attributedString = NSAttributedString(string: "River and river")
        XCTAssertEqual(document.replaceAll("river", with: "stream", matchCase: true), 1)
        XCTAssertEqual(a.content.attributedString.string, "River and stream", "with Match Case the replacement is literal")
    }
    
    func testReplaceStaleMatchIsRejected() throws {
        let (document, a, _, _, _) = makeDocument()
        a.content.attributedString = NSAttributedString(string: "hello")
        let match = document.findMatches("hello").first!
        a.content.attributedString = NSAttributedString(string: "hi")
        XCTAssertFalse(document.replace(match, with: "x"))
        XCTAssertEqual(a.content.attributedString.string, "hi")
    }
    
    // MARK: - Phase 2: Markdown export / import
    
    private func isBold(_ text: NSAttributedString, at index: Int) -> Bool {
        (text.attribute(.font, at: index, effectiveRange: nil) as! PlatformFont).isBoldTrait
    }
    
    private func isItalic(_ text: NSAttributedString, at index: Int) -> Bool {
        (text.attribute(.font, at: index, effectiveRange: nil) as! PlatformFont).isItalicTrait
    }
    
    func testMarkdownExportUsesHeadingDepthEmphasisAndTags() throws {
        let (document, a, a1, _, b) = makeDocument()
        a.title = "Chapter One"
        a.tags = ["draft", "rewrite"]
        let body = NSMutableAttributedString(string: "Plain then bold and italic.\nSecond paragraph.")
        let base = PlatformFont(name: "Georgia", size: 14)!
        body.addAttribute(.font, value: base, range: NSRange(location: 0, length: body.length))
        body.addAttribute(.font, value: base.addingTraits(bold: true, italic: false), range: NSRange(location: 11, length: 4))
        body.addAttribute(.font, value: base.addingTraits(bold: false, italic: true), range: NSRange(location: 20, length: 6))
        a.content.attributedString = body
        a1.title = "Scene"
        a1.content.attributedString = NSAttributedString(string: "# not a heading")
        b.title = "Chapter Two"
        b.content.attributedString = NSAttributedString(string: "")
        
        let md = Markdown.string(from: document.sections)
        let expected = """
        # Chapter One
        
        <!-- tags: draft, rewrite -->
        
        Plain then **bold** and *italic*.
        
        Second paragraph.
        
        ## Scene
        
        \\# not a heading
        
        ## A2
        
        a2
        
        # Chapter Two
        
        """
        XCTAssertEqual(md, expected)
    }
    
    func testMarkdownImportBuildsTreeFromHeadings() throws {
        let md = """
        Intro paragraph before any heading.
        
        # One
        <!-- tags: draft -->
        First paragraph with **bold** and *italic* and ***both***.
        continues on the next line.
        
        Second paragraph with snake_case and a \\*literal star\\*.
        
        ## One A
        ### Deep
        # Two
        Setext Title
        ------------
        under setext
        """
        let sections = Markdown.sections(from: md)
        XCTAssertEqual(sections.map(\.title), ["", "One", "Two"], "untitled intro block stores an empty title")
        XCTAssertEqual(sections[0].content.attributedString.string, "Intro paragraph before any heading.")
        
        let one = sections[1]
        XCTAssertEqual(one.tags, ["draft"])
        XCTAssertEqual(one.children.map(\.title), ["One A"])
        XCTAssertEqual(one.children[0].children.map(\.title), ["Deep"])
        let text = one.content.attributedString
        XCTAssertEqual(text.string, "First paragraph with bold and italic and both. continues on the next line.\nSecond paragraph with snake_case and a *literal star*.")
        XCTAssertTrue(isBold(text, at: 21))
        XCTAssertFalse(isItalic(text, at: 21))
        XCTAssertTrue(isItalic(text, at: 30))
        XCTAssertTrue(isBold(text, at: 41) && isItalic(text, at: 41))
        XCTAssertFalse(isBold(text, at: 0))
        
        let two = sections[2]
        XCTAssertEqual(two.children.map(\.title), ["Setext Title"])
        XCTAssertEqual(two.children[0].content.attributedString.string, "under setext")
    }
    
    func testMarkdownRoundTripPreservesStructureTextAndEmphasis() throws {
        let (document, a, a1, a2, b) = makeDocument()
        a.title = "Alpha"; a1.title = "Alpha one"; a2.title = "Alpha two"; b.title = "Beta"
        a1.tags = ["x"]
        let body = NSMutableAttributedString(string: "Some bold words here.")
        let base = TypographySettings().baseFont
        body.addAttribute(.font, value: base, range: NSRange(location: 0, length: body.length))
        body.addAttribute(.font, value: base.addingTraits(bold: true, italic: false), range: NSRange(location: 5, length: 4))
        a1.content.attributedString = body
        
        let again = Markdown.sections(from: Markdown.string(from: document.sections))
        XCTAssertEqual(again.map(\.title), ["Alpha", "Beta"])
        XCTAssertEqual(again[0].children.map(\.title), ["Alpha one", "Alpha two"])
        XCTAssertEqual(again[0].children[0].tags, ["x"])
        let text = again[0].children[0].content.attributedString
        XCTAssertEqual(text.string, "Some bold words here.")
        XCTAssertTrue(isBold(text, at: 6))
        XCTAssertFalse(isBold(text, at: 12))
        XCTAssertEqual(again[1].content.attributedString.string, "b")
    }
    
    func testMarkdownCarriesDocumentFontInAComment() throws {
        let (document, _, _, _, _) = makeDocument()
        let typography = TypographySettings(fontFamily: "Palatino", fontSize: 16)
        let md = Markdown.string(from: document.sections, typography: typography)
        XCTAssertTrue(md.hasPrefix("<!-- kisho: font Palatino 16 -->\n\n# A"))
        
        let imported = Markdown.document(from: md)
        XCTAssertEqual(imported.typography.fontFamily, "Palatino")
        XCTAssertEqual(imported.typography.fontSize, 16)
        XCTAssertEqual(imported.sections.map(\.title), ["A", "B"], "the comment adds no block")
        let font = imported.sections[0].content.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        XCTAssertEqual(font?.familyName, "Palatino")
        XCTAssertEqual(font?.pointSize, 16)
        
        XCTAssertEqual(Markdown.fontComment(in: "<!-- kisho: font Helvetica Neue 13.5 -->")?.fontFamily, "Helvetica Neue")
        XCTAssertEqual(Markdown.fontComment(in: "<!-- kisho: font Helvetica Neue 13.5 -->")?.fontSize, 13.5)
        XCTAssertNil(Markdown.fontComment(in: "# No comment here"))
        XCTAssertEqual(Markdown.document(from: "# Plain").typography, TypographySettings(), "no comment → defaults")
    }
    
    func testMarkdownImportOfEmptyOrHeadinglessTextStillYieldsADocument() throws {
        XCTAssertEqual(Markdown.sections(from: "").map(\.title), [""])
        let plain = Markdown.sections(from: "just a line\n\nand another")
        XCTAssertEqual(plain.count, 1)
        XCTAssertEqual(plain[0].content.attributedString.string, "just a line\nand another")
    }

    // MARK: - Phase 2: Word export

    func testDocxDocumentXMLUsesHeadingStylesAndRuns() throws {
        let (document, a, a1, _, b) = makeDocument()
        a.title = "Chapter <One> & Co"
        let body = NSMutableAttributedString(string: "Plain bold italic.\nSecond\tline")
        let base = PlatformFont(name: "Georgia", size: 14)!
        body.addAttribute(.font, value: base, range: NSRange(location: 0, length: body.length))
        body.addAttribute(.font, value: base.addingTraits(bold: true, italic: false), range: NSRange(location: 6, length: 4))
        body.addAttribute(.font, value: base.addingTraits(bold: false, italic: true), range: NSRange(location: 11, length: 6))
        a.content.attributedString = body
        a1.content.attributedString = NSAttributedString(string: "")
        b.content.attributedString = NSAttributedString(string: "\n\n")

        let xml = Docx.documentXML(sections: document.sections)
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"Heading1\"/></w:pPr><w:r><w:t xml:space=\"preserve\">Chapter &lt;One&gt; &amp; Co</w:t></w:r>"))
        XCTAssertTrue(xml.contains("<w:r><w:t xml:space=\"preserve\">Plain </w:t></w:r><w:r><w:rPr><w:b/><w:bCs/></w:rPr><w:t xml:space=\"preserve\">bold</w:t></w:r><w:r><w:t xml:space=\"preserve\"> </w:t></w:r><w:r><w:rPr><w:i/><w:iCs/></w:rPr><w:t xml:space=\"preserve\">italic</w:t></w:r><w:r><w:t xml:space=\"preserve\">.</w:t></w:r></w:p>"))
        XCTAssertTrue(xml.contains("<w:t xml:space=\"preserve\">Second</w:t><w:tab/><w:t xml:space=\"preserve\">line</w:t>"), "tabs become Word tabs")
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"Heading2\"/></w:pPr><w:r><w:t xml:space=\"preserve\">A1</w:t></w:r></w:p>\n<w:p><w:pPr><w:pStyle w:val=\"Heading2\"/>"), "an empty body adds no paragraphs")
        XCTAssertEqual(xml.components(separatedBy: "Heading1").count - 1, 2, "two top-level blocks")
        XCTAssertFalse(xml.contains("<w:p></w:p>"), "blank lines are dropped")
        XCTAssertTrue(xml.hasSuffix("</w:body>\n</w:document>"))
    }

    func testDocxStylesFollowDocumentTypography() throws {
        let georgia = Docx.stylesXML(typography: TypographySettings(fontFamily: "Georgia", fontSize: 14))
        XCTAssertTrue(georgia.contains("w:ascii=\"Georgia\""))
        XCTAssertTrue(georgia.contains("<w:sz w:val=\"28\"/>"), "14 pt is 28 half-points")
        XCTAssertTrue(georgia.contains("w:styleId=\"Heading6\""))
        XCTAssertTrue(georgia.contains("<w:outlineLvl w:val=\"0\"/>"))

        let system = Docx.stylesXML(typography: TypographySettings(fontFamily: ".AppleSystemUIFont", fontSize: 12))
        XCTAssertTrue(system.contains("w:ascii=\"Helvetica Neue\""), "Word has no system UI font")
        XCTAssertEqual(Docx.escape("a < b & \"c\"\u{01}"), "a &lt; b &amp; &quot;c&quot;", "control characters dropped")
    }

    func testDocxPackageIsAStoredZipWithSixParts() throws {
        XCTAssertEqual(ZipWriter.crc32(Data("123456789".utf8)), 0xCBF43926)

        let (document, _, _, _, _) = makeDocument()
        let data = Docx.data(from: document.sections, typography: TypographySettings())
        XCTAssertEqual([UInt8](data.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "local file header signature")
        // Walk the local file headers: name length at +26, name at +30,
        // then the (stored, so uncompressed) data of the size at +18.
        var names: [String] = []
        var offset = 0
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        while offset + 30 <= bytes.count, u32(offset) == 0x04034b50 {
            let nameLength = u16(offset + 26), extraLength = u16(offset + 28), size = u32(offset + 18)
            names.append(String(decoding: bytes[(offset + 30)..<(offset + 30 + nameLength)], as: UTF8.self))
            offset += 30 + nameLength + extraLength + size
        }
        XCTAssertEqual(names, ["[Content_Types].xml", "_rels/.rels", "word/_rels/document.xml.rels",
                               "word/document.xml", "word/styles.xml", "word/settings.xml"])
        XCTAssertEqual(u32(offset), 0x02014b50, "central directory follows the last entry")
        // End of central directory: signature then two zero shorts, then the entry count twice.
        let eocd = data.suffix(22)
        XCTAssertEqual([UInt8](eocd.prefix(4)), [0x50, 0x4B, 0x05, 0x06])
        XCTAssertEqual(eocd[eocd.startIndex + 8], 6)
        XCTAssertEqual(eocd[eocd.startIndex + 10], 6)
        XCTAssertTrue(Docx.settingsXML.contains("<w:defaultTabStop w:val=\"720\"/>"), "Pages needs the default tab stop stated")
    }

    // MARK: - Phase 2: underline

    func testSelectionFormattingAttributeHelpersCoverAllThreeTraits() throws {
        let base: [NSAttributedString.Key: Any] = [.font: PlatformFont(name: "Georgia", size: 14)!]
        XCTAssertFalse(SelectionFormatting.attributes(base, have: .underline))
        XCTAssertFalse(SelectionFormatting.attributes(base, have: .bold))

        let underlined = SelectionFormatting.attributes(base, setting: .underline, to: true)
        XCTAssertTrue(SelectionFormatting.attributes(underlined, have: .underline))
        XCTAssertEqual(underlined[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertFalse(SelectionFormatting.attributes(underlined, have: .bold), "underline leaves the font alone")

        let cleared = SelectionFormatting.attributes(underlined, setting: .underline, to: false)
        XCTAssertNil(cleared[.underlineStyle])

        let bold = SelectionFormatting.attributes(underlined, setting: .bold, to: true)
        XCTAssertTrue(SelectionFormatting.attributes(bold, have: .bold))
        XCTAssertTrue(SelectionFormatting.attributes(bold, have: .underline), "bold keeps the underline")
        XCTAssertEqual((bold[.font] as? PlatformFont)?.familyName, "Georgia")

        // The storage toggle: mixed runs gain the trait; uniform runs lose it.
        let text = NSMutableAttributedString(string: "plain bold", attributes: base)
        text.addAttributes(SelectionFormatting.attributes(base, setting: .bold, to: true), range: NSRange(location: 6, length: 4))
        let all = NSRange(location: 0, length: 10)
        XCTAssertTrue(SelectionFormatting.toggle(.bold, in: text, range: all), "not every run was bold, so bold is added")
        XCTAssertTrue(SelectionFormatting.attributes(text.attributes(at: 0, effectiveRange: nil), have: .bold))
        XCTAssertFalse(SelectionFormatting.toggle(.bold, in: text, range: all), "all bold now, so bold is removed")
        XCTAssertFalse(SelectionFormatting.attributes(text.attributes(at: 8, effectiveRange: nil), have: .bold))
    }

    func testUnderlineSurvivesRetypesetMarkdownAndWord() throws {
        let (document, a, _, _, _) = makeDocument()
        let base = TypographySettings().baseFont
        let body = NSMutableAttributedString(string: "under and both here", attributes: [.font: base])
        body.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: 5))
        body.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 10, length: 4))
        body.addAttribute(.font, value: base.addingTraits(bold: true, italic: false), range: NSRange(location: 10, length: 4))
        a.content.attributedString = body

        // Changing the document font keeps the underline.
        let retyped = KishoSection.retypeset(body, base: PlatformFont(name: "Palatino", size: 16)!, color: nil)
        XCTAssertEqual(retyped.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertNil(retyped.attribute(.underlineStyle, at: 6, effectiveRange: nil))

        // Markdown: <u>…</u>, combined with ** inside, and back again.
        let md = Markdown.string(from: [a])
        XCTAssertTrue(md.contains("<u>under</u> and <u>**both**</u> here"), md)
        let again = Markdown.sections(from: md)[0].content.attributedString
        XCTAssertEqual(again.string, "under and both here")
        XCTAssertEqual(again.attribute(.underlineStyle, at: 2, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertNil(again.attribute(.underlineStyle, at: 7, effectiveRange: nil))
        XCTAssertEqual(again.attribute(.underlineStyle, at: 11, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        let bothFont = again.attribute(.font, at: 11, effectiveRange: nil) as! PlatformFont
        XCTAssertTrue(bothFont.isBoldTrait)

        // Word: a w:u run property.
        let xml = Docx.runsXML(body)
        XCTAssertTrue(xml.hasPrefix("<w:r><w:rPr><w:u w:val=\"single\"/></w:rPr><w:t xml:space=\"preserve\">under</w:t></w:r>"), xml)
        XCTAssertTrue(xml.contains("<w:rPr><w:b/><w:bCs/><w:u w:val=\"single\"/></w:rPr><w:t xml:space=\"preserve\">both</w:t>"), xml)
    }

    // MARK: - Phase 3: format version, indent/outdent, new-block focus

    func testDocumentFormatVersionIsWrittenAndNewerFilesAreRefused() throws {
        let (document, _, _, _, _) = makeDocument()
        let data = try JSONEncoder().encode(document)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["formatVersion"] as? Int, KishoDocumentModel.currentFormatVersion)

        // Files from before the key read as version 0.
        var legacy = json
        legacy.removeValue(forKey: "formatVersion")
        let reopened = try JSONDecoder().decode(KishoDocumentModel.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(reopened.sections.map(\.title), ["A", "B"])

        var future = json
        future["formatVersion"] = KishoDocumentModel.currentFormatVersion + 1
        XCTAssertThrowsError(try JSONDecoder().decode(KishoDocumentModel.self, from: JSONSerialization.data(withJSONObject: future))) { error in
            XCTAssertTrue(error is KishoDocumentModel.FormatError)
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testIndentAndOutdentMoveBlocksLikeAnOutliner() throws {
        let (document, a, a1, a2, b) = makeDocument()
        let undo = manualUndoManager()
        // Manual grouping: one group per user action, as the app's event loop would give.
        func grouped(_ action: () -> Void) {
            undo.beginUndoGrouping(); action(); undo.endUndoGrouping()
        }

        XCTAssertFalse(document.canIndent(sectionID: a.id), "first block has nothing above it")
        XCTAssertFalse(document.canOutdent(sectionID: a.id), "top level can't go further out")
        XCTAssertTrue(document.canIndent(sectionID: a2.id))
        XCTAssertTrue(document.canOutdent(sectionID: a1.id))

        grouped { document.indentSection(withID: a2.id, focusing: .title, using: undo) }
        XCTAssertEqual(a1.children.map(\.title), ["A2"], "indent nests under the sibling above")
        XCTAssertEqual(a.children.map(\.title), ["A1"])
        XCTAssertEqual(document.selectedSectionID, a2.id)
        XCTAssertEqual(document.focusRequest?.field, .title, "Tab in a title keeps focus in titles")

        grouped { document.outdentSection(withID: a2.id, using: undo) }
        XCTAssertEqual(a.children.map(\.title), ["A1", "A2"], "outdent puts it straight after its parent")

        grouped { document.outdentSection(withID: a1.id, using: undo) }
        XCTAssertEqual(document.sections.map(\.title), ["A", "A1", "B"], "A1 leaves A")
        XCTAssertEqual(a.children.map(\.title), ["A2"], "A2 stays with A")
        XCTAssertEqual(titles(document), ["A", "A2", "A1", "B"])

        grouped { document.indentSection(withID: b.id, using: undo) }
        XCTAssertEqual(document.sections.map(\.title), ["A", "A1"])
        XCTAssertEqual(a1.children.map(\.title), ["B"])

        undo.undo(); undo.undo(); undo.undo(); undo.undo()
        XCTAssertEqual(document.sections.map(\.title), ["A", "B"])
        XCTAssertEqual(a.children.map(\.title), ["A1", "A2"])
        XCTAssertTrue(a1.children.isEmpty)

        grouped { document.indentSection(withID: a.id, using: undo) }
        XCTAssertEqual(document.sections.map(\.title), ["A", "B"], "no-op leaves the tree alone")
    }

    func testNewBlockFocusFollowsPreference() throws {
        let (document, _, _, _, _) = makeDocument()
        // The preference lives in the real UserDefaults; pin it and put it back.
        let key = KishoPreferences.Key.newBlockFocusesBody
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(KishoPreferences.newBlockFocus, .title, "default is the title")
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertEqual(KishoPreferences.newBlockFocus, .body)
        UserDefaults.standard.set(false, forKey: key)
        document.newBlockFocus = { .body }
        document.addSiblingSection()
        XCTAssertEqual(document.focusRequest?.field, .body)
        document.newBlockFocus = { .title }
        document.addChildSection()
        XCTAssertEqual(document.focusRequest?.field, .title)
    }

    // MARK: - Print / paged PDF

    func testPrintableTextTagsHeadingsByDepthAndKeepsBodies() throws {
        let (document, a, _, _, _) = makeDocument()
        a.content.attributedString = NSAttributedString(string: "line one\nline two\n\n")
        let text = PageLayout.printableText(from: document.sections)
        let string = text.string
        XCTAssertTrue(string.hasPrefix("A\nline one\nline two\nA1\n"), string)
        XCTAssertEqual(text.attribute(.kishoHeading, at: 0, effectiveRange: nil) as? Int, 1)
        let a1Index = (string as NSString).range(of: "A1\n").location
        XCTAssertEqual(text.attribute(.kishoHeading, at: a1Index, effectiveRange: nil) as? Int, 2)
        XCTAssertNil(text.attribute(.kishoHeading, at: 2, effectiveRange: nil), "bodies are not headings")
        let h1 = text.attribute(.font, at: 0, effectiveRange: nil) as! PlatformFont
        let h2 = text.attribute(.font, at: a1Index, effectiveRange: nil) as! PlatformFont
        XCTAssertGreaterThan(h1.pointSize, h2.pointSize)
        XCTAssertEqual(text.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? PlatformColor, .black)
    }

    func testPaginationNeverLeavesAHeadingAtTheFootOfAPage() throws {
        // Many short blocks on very short pages: without keep-with-next some
        // page would end on a heading.
        var sections: [KishoSection] = []
        for i in 1...40 {
            let body = NSAttributedString(string: String(repeating: "Body text for block \(i). ", count: 3))
            sections.append(makeSection(title: "Heading \(i)", body: body.string))
        }
        let text = PageLayout.printableText(from: sections)
        let pages = PageLayout.paginate(text, contentSize: CGSize(width: 300, height: 160))
        XCTAssertGreaterThan(pages.pageCount, 5)

        let storage = pages.storage
        for (index, range) in pages.pageRanges.enumerated() where index < pages.pageCount - 1 {
            // The last non-empty line on the page must not be a heading.
            var end = NSMaxRange(range)
            let ns = storage.string as NSString
            while end > range.location, CharacterSet.newlines.contains(Unicode.Scalar(ns.character(at: end - 1))!) { end -= 1 }
            guard end > range.location else { continue }
            let lastLine = ns.paragraphRange(for: NSRange(location: end - 1, length: 0))
            XCTAssertNil(storage.attribute(.kishoHeading, at: lastLine.location, effectiveRange: nil),
                         "page \(index + 1) ends with heading '\(ns.substring(with: lastLine).trimmingCharacters(in: .newlines))'")
        }
        // Every character is on exactly one page, in order.
        var covered = 0
        for range in pages.pageRanges { XCTAssertEqual(range.location, covered); covered = NSMaxRange(range) }
        XCTAssertEqual(covered, storage.length)
    }

    func testPagedPDFHasOnePagePerContainerWithFooter() throws {
        let (document, _, _, _, _) = makeDocument()
        let options = PageLayout.Options(pageSize: CGSize(width: 595, height: 842),
                                         margins: PlatformEdgeInsets(top: 72, left: 72, bottom: 72, right: 72),
                                         title: "Test")
        let data = try XCTUnwrap(PageLayout.pdfData(from: document.sections, options: options))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 1)
        let pageText = pdf.page(at: 0)?.string ?? ""
        XCTAssertTrue(pageText.contains("A1"))
        XCTAssertTrue(pageText.contains("1 of 1"), pageText)
        XCTAssertTrue(pageText.contains("Test"), pageText)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 595, height: 842))
    }

    // MARK: - OPML

    func testOPMLExportNestsOutlinesWithNotesAndCategories() throws {
        let (document, a, a1, _, b) = makeDocument()
        a.title = "Alpha & <Co>"
        a.content.attributedString = NSAttributedString(string: "First line.\nSecond \"quoted\" line.\n")
        a1.tags = ["draft", "to do"]
        b.content.attributedString = NSAttributedString(string: "")

        let opml = OPML.string(from: document.sections, title: "My Book")
        XCTAssertTrue(opml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<opml version=\"2.0\">\n<head><title>My Book</title></head>\n<body>\n"))
        XCTAssertTrue(opml.contains("  <outline text=\"Alpha &amp; &lt;Co&gt;\" _note=\"First line.&#10;Second &quot;quoted&quot; line.\">\n"))
        XCTAssertTrue(opml.contains("    <outline text=\"A1\" _note=\"a1\" category=\"draft,to do\"/>\n"))
        XCTAssertTrue(opml.contains("  <outline text=\"B\"/>\n"), "empty body → no _note")
        XCTAssertTrue(opml.hasSuffix("</body>\n</opml>\n"))
        XCTAssertTrue(XMLParser(data: Data(opml.utf8)).parse(), "well-formed XML")
    }

    func testOPMLImportBuildsBlocksFromOutlines() throws {
        let opml = """
        <?xml version="1.0"?>
        <opml version="2.0"><head><title>T</title></head>
        <body>
          <outline text="One" _note="Para one.&#10;&#10;Para two." category="x, y">
            <outline text="One A"/>
            <outline title="One B (title attr)" _note="  "/>
          </outline>
          <outline text="Two"><outline text="Deep"><outline text="Deeper"/></outline></outline>
          <outline text=""/>
        </body></opml>
        """
        let sections = try OPML.sections(from: Data(opml.utf8))
        XCTAssertEqual(sections.map(\.title), ["One", "Two", ""], "blank outline item stores an empty title")
        XCTAssertEqual(sections[0].content.attributedString.string, "Para one.\nPara two.", "blank lines collapse")
        XCTAssertEqual(sections[0].tags, ["x", "y"])
        XCTAssertEqual(sections[0].children.map(\.title), ["One A", "One B (title attr)"])
        XCTAssertEqual(sections[0].children[1].content.attributedString.length, 0, "whitespace-only note is no body")
        XCTAssertEqual(sections[1].children[0].children.map(\.title), ["Deeper"])
        XCTAssertEqual(sections[2].children.count, 0)

        let font = sections[0].content.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        XCTAssertEqual(font?.familyName, TypographySettings().baseFont.familyName)
    }

    func testOPMLRoundTripAndErrors() throws {
        let (document, a, a1, _, _) = makeDocument()
        a1.tags = ["t"]
        a.content.attributedString = NSAttributedString(string: "Line 1\nLine 2")
        let again = try OPML.sections(from: Data(OPML.string(from: document.sections, title: "x").utf8))
        XCTAssertEqual(again.map(\.title), ["A", "B"])
        XCTAssertEqual(again[0].children.map(\.title), ["A1", "A2"])
        XCTAssertEqual(again[0].children[0].tags, ["t"])
        XCTAssertEqual(again[0].content.attributedString.string, "Line 1\nLine 2")

        XCTAssertThrowsError(try OPML.sections(from: Data("<html><body>hi</body></html>".utf8))) { error in
            XCTAssertTrue((error as? OPML.ImportError) != nil)
        }
        XCTAssertThrowsError(try OPML.sections(from: Data("<opml><body><outline text='x'>".utf8)), "malformed XML")
        XCTAssertEqual(try OPML.sections(from: Data("<opml version=\"2.0\"><body/></opml>".utf8)).map(\.title), [""])
    }

    // MARK: - Block metadata

    func testBlockMetadataRoundTripsAndOldFilesStillOpen() throws {
        let (document, a, a1, _, _) = makeDocument()
        a.status = .revised; a.colorIndex = 3; a.synopsis = "Where it starts"; a.notes = "Check\nthe dates"
        a1.status = .done

        let data = try JSONEncoder().encode(document)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"status\":\"revised\""))
        XCTAssertTrue(json.contains("\"colorIndex\":3"))
        XCTAssertFalse(json.contains("\"synopsis\":\"\""), "empty metadata isn't written")

        let again = try JSONDecoder().decode(KishoDocumentModel.self, from: data)
        let a2 = again.sections[0]
        XCTAssertEqual(a2.status, .revised); XCTAssertEqual(a2.colorIndex, 3)
        XCTAssertEqual(a2.synopsis, "Where it starts"); XCTAssertEqual(a2.notes, "Check\nthe dates")
        XCTAssertEqual(a2.children[0].status, .done)
        XCTAssertNil(a2.children[1].status); XCTAssertNil(a2.children[1].colorIndex)

        // A block with an out-of-range colour (from a future palette) opens colourless.
        let hacked = json.replacingOccurrences(of: "\"colorIndex\":3", with: "\"colorIndex\":42")
        XCTAssertNil(try JSONDecoder().decode(KishoDocumentModel.self, from: Data(hacked.utf8)).sections[0].colorIndex)
        XCTAssertEqual(KishoDocumentModel.currentFormatVersion, 2)
    }

    func testBlockMetadataSettersAreUndoableAndTrim() throws {
        let (document, a, _, _, _) = makeDocument()
        let undo = manualUndoManager()
        func grouped(_ action: () -> Void) { undo.beginUndoGrouping(); action(); undo.endUndoGrouping() }

        grouped { document.setStatus(.draft, for: a, using: undo) }
        grouped { document.setColorIndex(5, for: a, using: undo) }
        grouped { document.setSynopsis("  A synopsis.  ", for: a, using: undo) }
        grouped { document.setNotes("note\n", for: a, using: undo) }
        XCTAssertEqual(a.status, .draft); XCTAssertEqual(a.colorIndex, 5)
        XCTAssertEqual(a.synopsis, "A synopsis."); XCTAssertEqual(a.notes, "note")

        grouped { document.setColorIndex(99, for: a, using: undo) }
        XCTAssertNil(a.colorIndex, "invalid palette index clears the colour")
        // No change → nothing registered. (Not wrapped in a group: an empty
        // group is discarded by AppKit's undo manager but kept by UIKit's,
        // where it would then swallow the next undo.)
        document.setSynopsis("A synopsis.", for: a, using: undo)
        XCTAssertEqual(undo.undoActionName, "Change Colour", "a no-op setter adds no undo step")

        undo.undo(); XCTAssertEqual(a.colorIndex, 5)
        undo.undo(); XCTAssertEqual(a.notes, "")
        undo.undo(); XCTAssertEqual(a.synopsis, "")
        undo.undo(); XCTAssertNil(a.colorIndex)
        undo.undo(); XCTAssertNil(a.status)
        XCTAssertFalse(undo.canUndo)
        undo.redo(); XCTAssertEqual(a.status, .draft)
    }

    func testMarkdownAndOPMLCarryBlockMetadata() throws {
        let (document, a, a1, _, _) = makeDocument()
        a.status = .final; a.colorIndex = 1; a.synopsis = "Opening\nmove"; a.notes = "Line one -- dashes\nLine two"
        a1.status = .done

        let md = Markdown.string(from: document.sections)
        XCTAssertTrue(md.contains("<!-- kisho: status final -->"))
        XCTAssertTrue(md.contains("<!-- kisho: colour 1 -->"))
        XCTAssertTrue(md.contains("<!-- synopsis: Opening move -->"), "synopsis is one line")
        XCTAssertTrue(md.contains("<!-- notes:\nLine one — dashes\nLine two\n-->"), md)
        let back = Markdown.sections(from: md)
        XCTAssertEqual(back[0].status, .final); XCTAssertEqual(back[0].colorIndex, 1)
        XCTAssertEqual(back[0].synopsis, "Opening move")
        XCTAssertEqual(back[0].notes, "Line one — dashes\nLine two")
        XCTAssertEqual(back[0].children[0].status, .done)
        XCTAssertNil(back[1].status)
        XCTAssertEqual(back[0].content.attributedString.string, "a", "comments add no body text")

        let opml = OPML.string(from: document.sections, title: "t")
        XCTAssertTrue(opml.contains("kisho_status=\"final\" kisho_colour=\"1\" kisho_synopsis=\"Opening&#10;move\""))
        XCTAssertTrue(opml.contains("_status=\"checked\" kisho_status=\"done\""))
        let fromOPML = try OPML.sections(from: Data(opml.utf8))
        XCTAssertEqual(fromOPML[0].status, .final); XCTAssertEqual(fromOPML[0].colorIndex, 1)
        XCTAssertEqual(fromOPML[0].synopsis, "Opening\nmove")
        XCTAssertEqual(fromOPML[0].children[0].status, .done)
        // Another outliner's checked item reads as Done.
        let other = try OPML.sections(from: Data("<opml><body><outline text=\"x\" _status=\"checked\"/></body></opml>".utf8))
        XCTAssertEqual(other[0].status, .done)
    }

    // MARK: - Typography presets / editor theme

    func testTypographyPresetsAreDistinctRealFontsAndApplyUndoably() throws {
        let settings = TypographyPreset.allCases.map(\.settings)
        XCTAssertEqual(Set(settings.map { "\($0.fontFamily) \($0.fontSize)" }).count, settings.count, "presets differ")
        for preset in TypographyPreset.allCases {
            XCTAssertEqual(preset.settings.baseFont.familyName, preset.settings.fontFamily, "\(preset.title) font is installed")
            XCTAssertEqual(TypographyPreset.matching(preset.settings), preset)
        }
        XCTAssertNil(TypographyPreset.matching(TypographySettings(fontFamily: "Georgia", fontSize: 11)))

        let (document, a, _, _, _) = makeDocument()
        let undo = manualUndoManager()
        undo.beginUndoGrouping()
        document.setTypography(TypographyPreset.typewriter.settings, undoManager: undo)
        undo.endUndoGrouping()
        XCTAssertEqual(document.typography, TypographyPreset.typewriter.settings)
        XCTAssertEqual((a.content.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)?.familyName, "Menlo")
        undo.undo()
        XCTAssertEqual(document.typography, TypographySettings())
    }

    func testEditorThemeDefaultsAndSchemes() throws {
        let key = KishoPreferences.Key.editorTheme
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(EditorTheme.current, .system)
        XCTAssertNil(EditorTheme.system.colorScheme)
        XCTAssertEqual(EditorTheme.dark.colorScheme, .dark)
        XCTAssertEqual(EditorTheme.sepia.colorScheme, .light, "sepia is a light scheme with paper tones")
        UserDefaults.standard.set("sepia", forKey: key)
        XCTAssertEqual(EditorTheme.current, .sepia)
        UserDefaults.standard.set("nonsense", forKey: key)
        XCTAssertEqual(EditorTheme.current, .system, "unknown value falls back")
    }

    func testSubtreeHasTag() throws {
        let (document, a, a1, _, b) = makeDocument()
        a1.tags = ["draft"]
        XCTAssertTrue(document.subtreeHasTag("draft", in: a), "ancestor of a tagged block is context")
        XCTAssertTrue(document.subtreeHasTag("draft", in: a1))
        XCTAssertFalse(document.subtreeHasTag("draft", in: b))
    }

    // MARK: - Move Up / Move Down (sibling order without drag-and-drop)

    func testMoveUpAndDownReorderSiblingsAndStopAtTheEnds() throws {
        let (document, a, a1, a2, b) = makeDocument()
        let undo = manualUndoManager()
        func grouped(_ action: () -> Void) {
            undo.beginUndoGrouping(); action(); undo.endUndoGrouping()
        }

        XCTAssertFalse(document.canMoveUp(sectionID: a.id), "first top-level block has nothing above it")
        XCTAssertTrue(document.canMoveDown(sectionID: a.id))
        XCTAssertFalse(document.canMoveDown(sectionID: b.id), "last top-level block has nothing below it")
        XCTAssertFalse(document.canMoveUp(sectionID: a1.id), "first child stays first")
        XCTAssertTrue(document.canMoveUp(sectionID: a2.id))
        XCTAssertFalse(document.canMoveDown(sectionID: a2.id))

        grouped { document.moveSectionUp(withID: a2.id, focusing: .title, using: undo) }
        XCTAssertEqual(a.children.map(\.title), ["A2", "A1"], "moving up changes places with the sibling above")
        XCTAssertEqual(document.selectedSectionID, a2.id)
        XCTAssertEqual(document.focusRequest?.field, .title, "focus field is passed through")

        document.moveSectionUp(withID: a2.id, using: undo)
        XCTAssertEqual(a.children.map(\.title), ["A2", "A1"], "moving up at the top is a no-op, not an outdent")
        XCTAssertEqual(document.sections.map(\.title), ["A", "B"])

        grouped { document.moveSectionDown(withID: a2.id, using: undo) }
        XCTAssertEqual(a.children.map(\.title), ["A1", "A2"])

        document.moveSectionDown(withID: a2.id, using: undo)
        XCTAssertEqual(a.children.map(\.title), ["A1", "A2"], "moving down at the bottom is a no-op")

        grouped { document.moveSectionDown(withID: a.id, using: undo) }
        XCTAssertEqual(document.sections.map(\.title), ["B", "A"], "a block's children come with it")
        XCTAssertEqual(titles(document), ["B", "A", "A1", "A2"])

        grouped { document.moveSectionUp(withID: a.id, using: undo) }
        XCTAssertEqual(document.sections.map(\.title), ["A", "B"])

        // Four real moves registered undo; the two no-ops (run outside a
        // group, so an empty group can't count as a step) registered nothing.
        undo.undo(); undo.undo(); undo.undo(); undo.undo()
        XCTAssertFalse(undo.canUndo, "no-ops leave no undo step behind")
        XCTAssertEqual(document.sections.map(\.title), ["A", "B"])
        XCTAssertEqual(a.children.map(\.title), ["A1", "A2"])

        undo.redo()
        XCTAssertEqual(a.children.map(\.title), ["A2", "A1"], "redo replays the first move")
    }

    func testMoveSelectedSectionUpAndDownFollowTheSelection() throws {
        let (document, _, a1, a2, _) = makeDocument()
        document.selectedSectionID = a2.id
        document.moveSelectedSectionUp()
        XCTAssertEqual(a1.parent?.children.map(\.title), ["A2", "A1"])
        document.moveSelectedSectionDown()
        XCTAssertEqual(a1.parent?.children.map(\.title), ["A1", "A2"])
        document.selectedSectionID = nil
        document.moveSelectedSectionDown()
        XCTAssertEqual(a1.parent?.children.map(\.title), ["A1", "A2"], "nothing selected: nothing happens")
    }

    func testCanSplitNeedsAParagraph() throws {
        let empty = makeSection(title: "Empty", body: "")
        let blank = makeSection(title: "Blank", body: "   \n\n  ")
        let one = makeSection(title: "One", body: "A single paragraph.")
        let titleOnly = makeSection(title: "Head\nSecond line typed into the title", body: "")
        let document = KishoDocumentModel(sections: [empty, blank, one, titleOnly])

        XCTAssertFalse(document.canSplit(sectionID: empty.id))
        XCTAssertFalse(document.canSplit(sectionID: blank.id), "whitespace is not a paragraph")
        XCTAssertTrue(document.canSplit(sectionID: one.id))
        XCTAssertTrue(document.canSplit(sectionID: titleOnly.id), "extra title lines split too")
        XCTAssertFalse(document.canSplit(sectionID: UUID()), "unknown block")
    }

    // MARK: - Localization

    func testUntitledIsNotStoredInDocuments() throws {
        let fresh = KishoSection(title: KishoSection.defaultTitle)
        XCTAssertEqual(fresh.title, "", "new blocks carry no language-specific title")
        XCTAssertEqual(fresh.displayTitle, KishoSection.untitledPlaceholder, "the placeholder is supplied at display time")

        // Blocks saved by pre-localization builds hold the English literal; they
        // decode as untitled so they pick up the localized placeholder too.
        let legacy = KishoSection(title: KishoSection.legacyDefaultTitle)
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(KishoSection.self, from: data)
        XCTAssertEqual(decoded.title, "")

        let named = KishoSection(title: "Chapter 1")
        let roundTrip = try JSONDecoder().decode(KishoSection.self, from: JSONEncoder().encode(named))
        XCTAssertEqual(roundTrip.title, "Chapter 1")
    }

    func testCountStringsPluralise() {
        // English plural rules from Localizable.xcstrings; grouping from the locale.
        XCTAssertEqual(KishoCounts.words(0), "0 words")
        XCTAssertEqual(KishoCounts.words(1), "1 word")
        XCTAssertEqual(KishoCounts.words(2), "2 words")
        XCTAssertEqual(KishoCounts.blocks(1), "1 block")
        XCTAssertEqual(KishoCounts.subBlocks(1), "1 sub-block")
        XCTAssertEqual(KishoCounts.subBlocks(3), "3 sub-blocks")
        XCTAssertEqual(KishoCounts.matches(1), "1 match")
        XCTAssertEqual(KishoCounts.matches(12), "12 matches")
        XCTAssertEqual(KishoCounts.position(3, of: 12), "3 of 12")
        // Large counts keep the locale's grouping separator.
        let grouped = KishoCounts.words(12345)
        XCTAssertTrue(grouped.hasPrefix("12,345") || grouped.hasPrefix("12.345") || grouped.hasPrefix("12 345") || grouped.hasPrefix("12\u{202F}345"),
                      "expected a grouped number, got \(grouped)")
    }

    #if os(iOS)
    func testConflictNoticeTextNamesTheDocumentAndCounts() throws {
        let one = CloudConflictResolver.noticeText(documentName: "Novel", copies: 1)
        XCTAssertTrue(one.hasPrefix("A conflicted copy of \u{201C}Novel\u{201D} was kept"), one)
        let two = CloudConflictResolver.noticeText(documentName: "Novel", copies: 2)
        XCTAssertTrue(two.hasPrefix("2 conflicted copies of \u{201C}Novel\u{201D} were kept"), two)
    }
    #endif
}
