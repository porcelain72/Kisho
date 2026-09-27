//
//  KishoTests.swift
//  KishoTests
//
//  Created by Peter Macdonald on 30/05/2025.
//

import XCTest
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
        XCTAssertEqual(root.children[0].content.attributedString.string, "")
        XCTAssertEqual(root.children[1].content.attributedString.string, "")
        XCTAssertEqual(document.selectedSectionID, root.children[0].id)
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
        XCTAssertEqual(root.children[0].content.attributedString.string, "")
        XCTAssertEqual(root.children[1].content.attributedString.string, "")
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

        func cardGutterWidth(at location: Int) -> CGFloat {
            let para = composite.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            let blocks = para?.textBlocks ?? []
            guard blocks.count >= 2,
                  let gutter = blocks[0] as? NSTextTableBlock,
                  gutter.startingColumn == 0 else {
                return 0
            }
            return gutter.value(for: .width)
        }

        let rootLoc = plain.range(of: "Root").location
        let childLoc = plain.range(of: "Child").location
        XCTAssertNotEqual(rootLoc, NSNotFound)
        XCTAssertNotEqual(childLoc, NSNotFound)
        XCTAssertEqual(cardGutterWidth(at: rootLoc), 0)
        XCTAssertEqual(cardGutterWidth(at: childLoc), 20)
        XCTAssertGreaterThan(cardGutterWidth(at: childLoc), cardGutterWidth(at: rootLoc))

        func headIndent(at location: Int) -> CGFloat {
            let para = composite.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            return para?.headIndent ?? -1
        }
        XCTAssertEqual(headIndent(at: rootLoc), 0)
        XCTAssertEqual(headIndent(at: childLoc), 0)
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

    func testCompositeDoesNotEndWithNewline() throws {
        let s1 = makeSection(title: "One", body: "AAA")
        let s2 = makeSection(title: "Two", body: "")
        let composite = KishoSection.documentCompositeAttributedString(sections: [s1, s2])
        XCTAssertFalse(composite.string.hasSuffix("\n"))
        XCTAssertFalse(composite.string.hasSuffix("\r"))
    }
}
