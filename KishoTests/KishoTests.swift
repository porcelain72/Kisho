//
//  KishoTests.swift
//  KishoTests
//
//  Created by Peter Macdonald on 30/05/2025.
//

import XCTest
import AppKit
import RichTextEditor
@testable import Kisho

final class KishoTests: XCTestCase {

    private func makeSection(title: String, body: String, children: [KishoSection] = []) -> KishoSection {
        let model = RichTextModel()
        model.attributedString = NSAttributedString(string: body)
        return KishoSection(title: title, content: model, children: children)
    }

    func testCompositeContainsAllNestedSections() throws {
        let childA = makeSection(title: "Alpha", body: "AAA")
        let childB = makeSection(title: "Bravo", body: "BBB")
        let root = makeSection(title: "Root", body: "ROOT", children: [childA, childB])

        let composite = root.compositeAttributedString()
        let plain = composite.string

        print("COMPOSITE PLAIN >>>\n\(plain)\n<<<")

        XCTAssertTrue(plain.contains("ROOT"), "root body missing")
        XCTAssertTrue(plain.contains("Alpha"), "child A title missing")
        XCTAssertTrue(plain.contains("AAA"), "child A body missing")
        XCTAssertTrue(plain.contains("Bravo"), "child B title missing")
        XCTAssertTrue(plain.contains("BBB"), "child B body missing")
    }

    func testCompositeRoundTripPreservesEachSection() throws {
        let childA = makeSection(title: "Alpha", body: "AAA")
        let childB = makeSection(title: "Bravo", body: "BBB")
        let root = makeSection(title: "Root", body: "ROOT", children: [childA, childB])

        let composite = root.compositeAttributedString()
        root.applyCompositeAttributedString(composite)

        XCTAssertEqual(root.content.attributedString.string, "ROOT")
        XCTAssertEqual(childA.content.attributedString.string, "AAA")
        XCTAssertEqual(childB.content.attributedString.string, "BBB")
        XCTAssertEqual(childA.title, "Alpha")
        XCTAssertEqual(childB.title, "Bravo")
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

        let composite = selected.compositeAttributedString()
        let plain = composite.string
        print("REOPENED COMPOSITE >>>\n\(plain)\n<<<")
        print("REOPENED children count: \(selected.children.count)")

        XCTAssertEqual(selected.children.count, 3, "children lost on reopen")
        XCTAssertTrue(plain.contains("ROOT body"))
        XCTAssertTrue(plain.contains("AAA body"))
        XCTAssertTrue(plain.contains("BBB body"))
        XCTAssertTrue(plain.contains("CCC body"))
    }

    func testEditorModelUpdateRootShowsFullSubtree() throws {
        let childA = makeSection(title: "Alpha", body: "AAA body")
        let childB = makeSection(title: "Bravo", body: "BBB body")
        let childC = makeSection(title: "Charlie", body: "CCC body")
        let root = makeSection(title: "Root", body: "ROOT body", children: [childA, childB, childC])

        // Simulate first appear on a leaf (e.g. last child), as if restored selection
        let model = SectionSubtreeEditorModel(section: childC)
        print("AFTER INIT leaf >>>\(model.compositeContent.attributedString.string)<<<")
        XCTAssertEqual(model.compositeContent.attributedString.string, "CCC body")

        // Now simulate clicking the parent in the sidebar
        model.updateRoot(root)
        let plain = model.compositeContent.attributedString.string
        print("AFTER updateRoot to parent >>>\n\(plain)\n<<<")

        XCTAssertTrue(plain.contains("ROOT body"), "root body missing after updateRoot")
        XCTAssertTrue(plain.contains("AAA body"), "A missing after updateRoot")
        XCTAssertTrue(plain.contains("BBB body"), "B missing after updateRoot")
        XCTAssertTrue(plain.contains("CCC body"), "C missing after updateRoot")
    }

    func testDocumentCompositeShowsAllTopLevelSections() throws {
        let childA = makeSection(title: "Alpha", body: "AAA body")
        let s1 = makeSection(title: "One", body: "ONE body", children: [childA])
        let s2 = makeSection(title: "Two", body: "TWO body")
        let s3 = makeSection(title: "Three", body: "THREE body")

        let composite = KishoSection.documentCompositeAttributedString(sections: [s1, s2, s3])
        let plain = composite.string
        print("DOC COMPOSITE >>>\n\(plain)\n<<<")

        for token in ["One", "ONE body", "Alpha", "AAA body", "Two", "TWO body", "Three", "THREE body"] {
            XCTAssertTrue(plain.contains(token), "missing \(token)")
        }
    }

    func testDocumentCompositeRoundTrip() throws {
        let childA = makeSection(title: "Alpha", body: "AAA body")
        let s1 = makeSection(title: "One", body: "ONE body", children: [childA])
        let s2 = makeSection(title: "Two", body: "TWO body")
        let sections = [s1, s2]

        let composite = KishoSection.documentCompositeAttributedString(sections: sections)
        KishoSection.applyDocumentComposite(composite, to: sections)

        XCTAssertEqual(s1.title, "One")
        XCTAssertEqual(s1.content.attributedString.string, "ONE body")
        XCTAssertEqual(childA.title, "Alpha")
        XCTAssertEqual(childA.content.attributedString.string, "AAA body")
        XCTAssertEqual(s2.title, "Two")
        XCTAssertEqual(s2.content.attributedString.string, "TWO body")
    }

    func testDocumentEditorModelComposesWholeDocument() throws {
        let childA = makeSection(title: "Alpha", body: "AAA body")
        let s1 = makeSection(title: "One", body: "ONE body", children: [childA])
        let s2 = makeSection(title: "Two", body: "TWO body")

        let model = KishoDocumentModel(sections: [s1, s2])
        let editor = DocumentCompositeEditorModel(document: model)
        let plain = editor.compositeContent.attributedString.string
        print("EDITOR DOC COMPOSITE >>>\n\(plain)\n<<<")

        for token in ["One", "ONE body", "Alpha", "AAA body", "Two", "TWO body"] {
            XCTAssertTrue(plain.contains(token), "missing \(token)")
        }
    }

    func testCompositeCaretIndexAtEndOfSectionContent() throws {
        let childA = makeSection(title: "Alpha", body: "AAA body")
        let childB = makeSection(title: "Bravo", body: "BBB body")
        let root = makeSection(title: "Root", body: "ROOT body", children: [childA, childB])

        let composite = KishoSection.documentCompositeAttributedString(sections: [root])
        let plain = composite.string as NSString

        guard let caretA = KishoSection.compositeCaretIndex(forSectionID: childA.id, in: composite) else {
            return XCTFail("no caret for childA")
        }
        // Caret should sit immediately after "AAA body".
        let bodyRange = plain.range(of: "AAA body")
        XCTAssertEqual(caretA, bodyRange.location + bodyRange.length)
    }

    func testCompositeCaretIndexEmptyContentFallsBackToHeading() throws {
        let empty = makeSection(title: "Empty", body: "")
        let root = makeSection(title: "Root", body: "ROOT body", children: [empty])

        let composite = KishoSection.documentCompositeAttributedString(sections: [root])
        guard let caret = KishoSection.compositeCaretIndex(forSectionID: empty.id, in: composite) else {
            return XCTFail("no caret for empty section")
        }
        XCTAssertLessThanOrEqual(caret, composite.length)
        XCTAssertGreaterThan(caret, 0)
    }

    func testEmptySectionCaretStaysInsideHeadingBlock() throws {
        let empty = makeSection(title: "Empty", body: "")
        let composite = KishoSection.documentCompositeAttributedString(sections: [empty])
        guard let caret = KishoSection.compositeCaretIndex(forSectionID: empty.id, in: composite) else {
            return XCTFail("no caret for empty section")
        }
        XCTAssertGreaterThan(caret, 0)
        let probe = min(caret, composite.length) - 1
        let attrs = composite.attributes(at: probe, effectiveRange: nil)
        XCTAssertEqual(attrs[.kishoSectionID] as? String, empty.id.uuidString)
        let before = (composite.string as NSString).substring(with: NSRange(location: probe, length: 1))
        XCTAssertNotEqual(before, "\n", "caret after a paragraph break sits in a hanging box below the wash")
    }

    func testDeeplyNestedComposite() throws {
        let grandchild = makeSection(title: "Gamma", body: "GGG")
        let child = makeSection(title: "Beta", body: "BBB", children: [grandchild])
        let root = makeSection(title: "Root", body: "ROOT", children: [child])

        let composite = root.compositeAttributedString()
        let plain = composite.string
        print("DEEP COMPOSITE PLAIN >>>\n\(plain)\n<<<")

        XCTAssertTrue(plain.contains("ROOT"))
        XCTAssertTrue(plain.contains("BBB"))
        XCTAssertTrue(plain.contains("GGG"))
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

    func testMakeChildrenKeepsUntaggedParagraphsFromComposite() throws {
        let root = makeSection(title: "Root", body: "First paragraph.")
        let document = KishoDocumentModel(sections: [root])
        document.selectedSectionID = root.id

        let composite = NSMutableAttributedString(
            attributedString: KishoSection.documentCompositeAttributedString(sections: [root])
        )
        composite.append(NSAttributedString(string: "\nSecond paragraph.\nThird paragraph."))
        document.liveCompositeProvider = { composite }

        document.makeChildren()

        XCTAssertEqual(root.children.count, 3)
        XCTAssertEqual(root.children[0].title, "First paragraph.")
        XCTAssertEqual(root.children[1].title, "Second paragraph.")
        XCTAssertEqual(root.children[2].title, "Third paragraph.")
    }

    func testDistributeKeepsUntaggedTrailingParagraphs() throws {
        let root = makeSection(title: "Root", body: "First paragraph.")
        let composite = NSMutableAttributedString(
            attributedString: KishoSection.documentCompositeAttributedString(sections: [root])
        )
        composite.append(NSAttributedString(string: "\nSecond paragraph.\nThird paragraph."))

        KishoSection.applyDocumentComposite(composite, to: [root])

        let body = root.content.attributedString.string
        XCTAssertTrue(body.contains("First paragraph."), body)
        XCTAssertTrue(body.contains("Second paragraph."), body)
        XCTAssertTrue(body.contains("Third paragraph."), body)
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

    func testEmptySectionCompositeHasContentRun() throws {
        let empty = makeSection(title: "Empty", body: "")
        let composite = KishoSection.documentCompositeAttributedString(sections: [empty])

        var sawContent = false
        var index = 0
        while index < composite.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attrs = composite.attributes(at: index, effectiveRange: &effectiveRange)
            if let id = attrs[.kishoSectionID] as? String, id == empty.id.uuidString,
               let role = attrs[.kishoSectionRole] as? String,
               role == KishoSectionRole.content.rawValue {
                sawContent = true
                break
            }
            index = effectiveRange.location + effectiveRange.length
        }
        XCTAssertTrue(sawContent, "empty sections must emit a content-tagged run so typing stays in the body")
    }

    func testCompositeShowsExtraTitleLinesAsBody() throws {
        let section = makeSection(title: "Heading\nBody line", body: "")
        let composite = KishoSection.documentCompositeAttributedString(sections: [section])
        let plain = composite.string

        XCTAssertTrue(plain.contains("Heading"))
        XCTAssertTrue(plain.contains("Body line"))

        KishoSection.applyDocumentComposite(composite, to: [section])
        XCTAssertEqual(section.title, "Heading")
        XCTAssertTrue(section.content.attributedString.string.contains("Body line"))
    }

    func testCompositeIndentsNestedSections() throws {
        let child = makeSection(title: "Child", body: "child body")
        let root = makeSection(title: "Root", body: "root body", children: [child])
        let composite = KishoSection.documentCompositeAttributedString(sections: [root])
        let plain = composite.string as NSString

        func gutterWidth(at location: Int) -> CGFloat {
            let para = composite.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            let blocks = para?.textBlocks ?? []
            guard blocks.count >= 2 else { return 0 }
            return blocks[0].width(for: .padding, edge: .minX)
        }

        func nestedTablesAreDistinct(at location: Int) -> Bool {
            let para = composite.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            let tables = (para?.textBlocks ?? []).compactMap { ($0 as? NSTextTableBlock)?.table }
            return Set(tables.map { ObjectIdentifier($0) }).count == tables.count
        }

        let rootLoc = plain.range(of: "Root").location
        let childLoc = plain.range(of: "Child").location
        XCTAssertNotEqual(rootLoc, NSNotFound)
        XCTAssertNotEqual(childLoc, NSNotFound)
        XCTAssertEqual(gutterWidth(at: rootLoc), 0)
        XCTAssertEqual(gutterWidth(at: childLoc), 20)
        XCTAssertTrue(nestedTablesAreDistinct(at: childLoc), "nested blocks must belong to different tables")

        func headIndent(at location: Int) -> CGFloat {
            let para = composite.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            return para?.headIndent ?? -1
        }
        XCTAssertEqual(headIndent(at: rootLoc), 0)
        XCTAssertEqual(headIndent(at: childLoc), 0)
    }

    /// Runs a real layout pass over a nested composite. TextKit used to stop
    /// laying out at the first nested card, leaving everything after it
    /// undrawn (and un-clickable), so this checks every glyph gets placed and
    /// that later blocks sit below earlier ones.
    func testNestedCompositeLaysOutCompletely() throws {
        let grandchild = makeSection(title: "Gamma", body: "gamma body")
        let child = makeSection(title: "Beta", body: "beta body", children: [grandchild])
        let root = makeSection(title: "Root", body: "root body", children: [child])
        let tail = makeSection(title: "Tail", body: "tail body")
        let composite = KishoSection.documentCompositeAttributedString(sections: [root, tail])

        let storage = NSTextStorage(attributedString: composite)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 600, height: 100_000))
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)

        let laidOut = layoutManager.glyphRange(for: container)
        XCTAssertEqual(NSMaxRange(laidOut), layoutManager.numberOfGlyphs, "layout stopped early")

        let plain = composite.string as NSString
        func top(of token: String) -> CGFloat {
            let charRange = plain.range(of: token)
            XCTAssertNotEqual(charRange.location, NSNotFound, token)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            return layoutManager.boundingRect(forGlyphRange: glyphRange, in: container).minY
        }
        XCTAssertLessThan(top(of: "Root"), top(of: "Beta"))
        XCTAssertLessThan(top(of: "Beta"), top(of: "Gamma"))
        XCTAssertLessThan(top(of: "Gamma"), top(of: "Tail"))

        func left(of token: String) -> CGFloat {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: plain.range(of: token), actualCharacterRange: nil)
            return layoutManager.boundingRect(forGlyphRange: glyphRange, in: container).minX
        }
        XCTAssertLessThan(left(of: "Root"), left(of: "Beta"), "nested cards should be inset")
        XCTAssertLessThan(left(of: "Beta"), left(of: "Gamma"))
    }

    func testDistributeStripsSectionChrome() throws {
        let child = makeSection(title: "Child", body: "child body")
        let root = makeSection(title: "Root", body: "root body", children: [child])
        let composite = KishoSection.documentCompositeAttributedString(sections: [root])
        KishoSection.applyDocumentComposite(composite, to: [root])

        let stored = child.content.attributedString
        XCTAssertGreaterThan(stored.length, 0)
        let para = stored.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(para?.headIndent ?? 0, 0)
        XCTAssertTrue(para?.textBlocks.isEmpty ?? true)
        XCTAssertNil(stored.attribute(.kishoSectionDepth, at: 0, effectiveRange: nil))
        XCTAssertNil(stored.attribute(.kishoSectionID, at: 0, effectiveRange: nil))
    }

    func testHeadingAndBodyHaveDistinctWashes() throws {
        let section = makeSection(title: "Heading", body: "Body text")
        let composite = KishoSection.documentCompositeAttributedString(sections: [section])
        let plain = composite.string as NSString

        func textBlock(at location: Int) -> NSTextBlock? {
            let para = composite.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            return para?.textBlocks.first as? NSTextBlock
        }

        let headingLoc = plain.range(of: "Heading").location
        let bodyLoc = plain.range(of: "Body text").location
        let headingBlock = textBlock(at: headingLoc)
        let bodyBlock = textBlock(at: bodyLoc)
        XCTAssertNotNil(headingBlock, "heading should have a wash")
        XCTAssertNotNil(bodyBlock, "body should have a wash")
        XCTAssertNotEqual(
            headingBlock?.backgroundColor,
            bodyBlock?.backgroundColor,
            "heading wash should be distinct from body wash"
        )
    }

    func testCompositeEndsWithOneUntaggedBreak() throws {
        let s1 = makeSection(title: "One", body: "AAA")
        let s2 = makeSection(title: "Two", body: "")
        let composite = KishoSection.documentCompositeAttributedString(sections: [s1, s2])
        XCTAssertTrue(composite.string.hasSuffix("\n"))
        XCTAssertFalse(composite.string.hasSuffix("\n\n"))
        let last = composite.length - 1
        XCTAssertNil(composite.attribute(.kishoSectionID, at: last, effectiveRange: nil), "closing break must not belong to a card")
        let para = composite.attribute(.paragraphStyle, at: last, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertTrue(para?.textBlocks.isEmpty ?? true)

        // Round-tripping must not fold the closing break into the last body.
        KishoSection.applyDocumentComposite(composite, to: [s1, s2])
        XCTAssertEqual(s1.content.attributedString.string, "AAA")
        XCTAssertEqual(s2.content.attributedString.string, "")
        let again = KishoSection.documentCompositeAttributedString(sections: [s1, s2])
        XCTAssertEqual(again.string, composite.string, "composite must be stable across rebuilds")
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
        body.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: NSRange(location: 0, length: 5))
        let model = RichTextModel()
        model.attributedString = body
        let root = KishoSection(title: "Root", content: model)
        let document = KishoDocumentModel(sections: [root])

        document.makeChildren()

        XCTAssertEqual(root.children.count, 1)
        XCTAssertEqual(root.children[0].title, "Short one.")
        XCTAssertEqual(root.children[0].content.attributedString.string, "Short one. And the rest of it.")
        let font = root.children[0].content.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false, "formatting must survive a split")
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
        XCTAssertEqual(document.pendingTitleEditID, document.selectedSectionID)
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
        let big = root.content.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(big?.pointSize, 30)

        undo.undo()
        let restored = root.content.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertNotEqual(restored?.pointSize, 30)
        XCTAssertEqual(document.typography.fontSize, 12, "undo restores the previous settings too")
    }

    func testExportedAttributedTextIsBlack() throws {
        let root = makeSection(title: "Root", body: "Hello")
        root.content.applyTypography(font: NSFont.systemFont(ofSize: 12), color: NSColor.labelColor)
        let exported = Exporter.attributedText(from: [root])
        var allBlack = true
        exported.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: exported.length)) { value, _, _ in
            if (value as? NSColor) != NSColor.black { allBlack = false }
        }
        XCTAssertTrue(allBlack, "export must not carry the appearance-adaptive label colour")
    }

    // MARK: - Card editor model support

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
        let undo = UndoManager()
        undo.groupsByEvent = false

        // Simulate the editor applying three quick keystrokes.
        let steps = ["ab", "abc", "abcd"].map { NSAttributedString(string: $0) }
        var previous = a.content.attributedString
        for step in steps {
            a.content.attributedString = step
            undo.beginUndoGrouping()
            document.recordBodyEdit(for: a, from: previous, to: step, using: undo)
            undo.endUndoGrouping()
            previous = step
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
        document.selectedSectionID = a.id
        document.addSiblingSection()
        XCTAssertEqual(document.focusRequest?.sectionID, document.selectedSectionID)
        XCTAssertEqual(document.focusRequest?.field, .title)
    }

    func testRetypesetPreservesBoldAndItalicPerRun() throws {
        let fm = NSFontManager.shared
        let text = NSMutableAttributedString(string: "plain bold italic")
        let base = NSFont.systemFont(ofSize: 12)
        text.addAttribute(.font, value: base, range: NSRange(location: 0, length: 17))
        text.addAttribute(.font, value: fm.convert(base, toHaveTrait: .boldFontMask), range: NSRange(location: 6, length: 4))
        text.addAttribute(.font, value: fm.convert(base, toHaveTrait: .italicFontMask), range: NSRange(location: 11, length: 6))

        let newBase = NSFont(name: "Helvetica", size: 16) ?? NSFont.systemFont(ofSize: 16)
        let result = KishoSection.retypeset(text, base: newBase, color: nil)

        func font(at i: Int) -> NSFont { result.attribute(.font, at: i, effectiveRange: nil) as! NSFont }
        XCTAssertEqual(font(at: 0).pointSize, 16)
        XCTAssertFalse(fm.traits(of: font(at: 0)).contains(.boldFontMask))
        XCTAssertTrue(fm.traits(of: font(at: 7)).contains(.boldFontMask), "bold run must stay bold")
        XCTAssertEqual(font(at: 7).pointSize, 16)
        XCTAssertTrue(fm.traits(of: font(at: 12)).contains(.italicFontMask), "italic run must stay italic")
    }

    func testDocumentTotalWordCount() throws {
        let (document, a, _, _, _) = makeDocument()
        XCTAssertEqual(document.totalWordCount, 4)
        a.content.attributedString = NSAttributedString(string: "one two three")
        XCTAssertEqual(document.totalWordCount, 6, "count follows content changes despite caching")
    }
}
