//
//  KishoPrint.swift
//  Kisho
//
//  Paged output for print and PDF: the document laid out as headings by
//  depth and body text, broken into pages of the user's paper size with
//  the Page Setup margins, page numbers in the footer, and no heading left
//  stranded at the foot of a page (TextKit has no keep-with-next, so the
//  paginator pushes such headings onto the next page itself).
//

import SwiftUI
import AppKit
import PDFKit
import RichTextEditor

extension NSAttributedString.Key {
    /// Marks a block heading paragraph (value: depth, 1-based) in printable text.
    static let kishoHeading = NSAttributedString.Key("KishoHeading")
}

enum PageLayout {

    struct Options {
        var pageSize: CGSize
        var margins: NSEdgeInsets
        var title: String
        var pageNumbers = true

        /// The user's paper from Page Setup (A4 or Letter by locale) and the
        /// margins from Settings (Page Setup has no margin controls).
        static func fromPrintInfo(_ info: NSPrintInfo = .shared, title: String) -> Options {
            let m = KishoPreferences.printMargins.points
            return Options(pageSize: info.paperSize,
                           margins: NSEdgeInsets(top: m, left: m, bottom: m, right: m),
                           title: title)
        }

        var contentSize: CGSize {
            CGSize(width: max(72, pageSize.width - margins.left - margins.right),
                   height: max(72, pageSize.height - margins.top - margins.bottom))
        }
    }

    // MARK: Text

    private static let headingPointSizes: [CGFloat] = [24, 20, 17, 15, 14, 13]

    /// The document as one attributed string for paper: headings sized by
    /// depth and tagged with `.kishoHeading`, bodies as written, all black.
    static func printableText(from sections: [KishoSection]) -> NSAttributedString {
        let output = NSMutableAttributedString()

        func heading(_ title: String, depth: Int, first: Bool) -> NSAttributedString {
            let size = headingPointSizes[min(depth, headingPointSizes.count) - 1]
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = first ? 0 : (depth == 1 ? 22 : 16)
            style.paragraphSpacing = 6
            return NSAttributedString(string: title + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: NSColor.black,
                .paragraphStyle: style,
                .kishoHeading: depth
            ])
        }

        func body(_ text: NSAttributedString) -> NSAttributedString {
            let mutable = NSMutableAttributedString(attributedString: text)
            let full = NSRange(location: 0, length: mutable.length)
            mutable.enumerateAttribute(.paragraphStyle, in: full) { value, range, _ in
                let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                style.paragraphSpacing = 8
                mutable.addAttribute(.paragraphStyle, value: style, range: range)
            }
            mutable.removeAttribute(.kishoHeading, range: full)
            mutable.addAttribute(.foregroundColor, value: NSColor.black, range: full)
            // The text view keeps a trailing newline at times; one is enough.
            while mutable.length > 0, mutable.string.hasSuffix("\n") {
                mutable.deleteCharacters(in: NSRange(location: mutable.length - 1, length: 1))
            }
            if mutable.length > 0 { mutable.append(NSAttributedString(string: "\n", attributes: mutable.attributes(at: mutable.length - 1, effectiveRange: nil))) }
            return mutable
        }

        var first = true
        func walk(_ list: [KishoSection], depth: Int) {
            for section in list {
                output.append(heading(section.displayTitle, depth: depth, first: first))
                first = false
                output.append(body(section.content.attributedString))
                walk(section.children, depth: depth + 1)
            }
        }
        walk(sections, depth: 1)
        return output
    }

    // MARK: Pagination

    struct Paginated {
        let storage: NSTextStorage
        let layoutManager: NSLayoutManager
        /// One container per page.
        let containers: [NSTextContainer]
        var pageCount: Int { containers.count }

        /// Character range on each page (for tests and callers that need it).
        var pageRanges: [NSRange] {
            containers.map { layoutManager.characterRange(forGlyphRange: layoutManager.glyphRange(for: $0), actualGlyphRange: nil) }
        }
    }

    /// Lays `text` out into pages of `contentSize`. When a heading would be
    /// the last line on a page, that page is cut short just above it so the
    /// heading flows onto the next page with its text (TextKit has no
    /// keep-with-next, and padding the heading instead would leave a gap at
    /// the top of the following page). Bounded, so odd input terminates.
    static func paginate(_ text: NSAttributedString, contentSize: CGSize) -> Paginated {
        let storage = NSTextStorage(attributedString: text)
        var heights: [Int: CGFloat] = [:]   // page index → shortened height

        for _ in 0..<64 {
            let result = layOut(storage, contentSize: contentSize, heights: heights)
            guard let orphan = firstOrphanHeading(in: result) else { return result }
            // Never shrink a page to almost nothing; a lone heading is then the lesser evil.
            guard orphan.headingTop > 48 else { return result }
            let current = heights[orphan.page] ?? contentSize.height
            guard orphan.headingTop - 1 < current else { return result }
            heights[orphan.page] = orphan.headingTop - 1
        }
        return layOut(storage, contentSize: contentSize, heights: heights)
    }

    private static func layOut(_ storage: NSTextStorage, contentSize: CGSize, heights: [Int: CGFloat]) -> Paginated {
        // A fresh layout manager each pass so earlier geometry can't linger.
        for lm in storage.layoutManagers { storage.removeLayoutManager(lm) }
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        var containers: [NSTextContainer] = []
        while true {
            let height = heights[containers.count] ?? contentSize.height
            let container = NSTextContainer(size: CGSize(width: contentSize.width, height: height))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            containers.append(container)
            layoutManager.ensureLayout(for: container)
            let range = layoutManager.glyphRange(for: container)
            if NSMaxRange(range) >= layoutManager.numberOfGlyphs || (range.length == 0 && containers.count > 1) { break }
            if containers.count > 2000 { break }
        }
        return Paginated(storage: storage, layoutManager: layoutManager, containers: containers)
    }

    private struct Orphan { let page: Int; let headingTop: CGFloat }

    /// The first page (not the last) whose final line is a heading, and the
    /// top of that heading within the page.
    private static func firstOrphanHeading(in result: Paginated) -> Orphan? {
        let lm = result.layoutManager
        for (index, container) in result.containers.enumerated() where index < result.containers.count - 1 {
            let glyphs = lm.glyphRange(for: container)
            guard glyphs.length > 0 else { continue }
            var lineRange = NSRange()
            _ = lm.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: &lineRange)
            let charIndex = lm.characterIndexForGlyph(at: lineRange.location)
            guard charIndex < result.storage.length,
                  result.storage.attribute(.kishoHeading, at: charIndex, effectiveRange: nil) != nil else { continue }
            let paragraph = (result.storage.string as NSString).paragraphRange(for: NSRange(location: charIndex, length: 0))
            let firstGlyph = lm.glyphIndexForCharacter(at: paragraph.location)
            let headingTop = lm.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil).minY
            return Orphan(page: index, headingTop: headingTop)
        }
        return nil
    }

    // MARK: PDF

    /// The whole document as a paged PDF.
    static func pdfData(from sections: [KishoSection], options: Options) -> Data? {
        let text = printableText(from: sections)
        let pages = paginate(text, contentSize: options.contentSize)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: options.pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)

        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor(white: 0.45, alpha: 1)
        ]

        for (index, container) in pages.containers.enumerated() {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            context.saveGState()
            // Flip to top-left origin, then step in by the margins.
            context.translateBy(x: 0, y: options.pageSize.height)
            context.scaleBy(x: 1, y: -1)

            let glyphs = pages.layoutManager.glyphRange(for: container)
            let origin = CGPoint(x: options.margins.left, y: options.margins.top)
            pages.layoutManager.drawBackground(forGlyphRange: glyphs, at: origin)
            pages.layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)

            if options.pageNumbers {
                let footer = NSAttributedString(
                    string: options.title.isEmpty ? "\(index + 1) of \(pages.pageCount)"
                                                  : "\(options.title)  ·  \(index + 1) of \(pages.pageCount)",
                    attributes: footerAttributes)
                let size = footer.size()
                let y = options.pageSize.height - options.margins.bottom / 2 - size.height / 2
                footer.draw(at: CGPoint(x: (options.pageSize.width - size.width) / 2, y: y))
            }

            context.restoreGState()
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}

// MARK: - Printing

enum Printer {
    /// File ▸ Print… — the paged PDF through the system print panel, so
    /// what prints is exactly what Export As ▸ PDF would write.
    static func printDocument(_ model: KishoDocumentModel, title: String) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        // The PDF already carries the margins; the print operation must not add its own.
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        guard let data = PageLayout.pdfData(from: model.sections, options: .fromPrintInfo(info, title: title)),
              let pdf = PDFDocument(data: data),
              let operation = pdf.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false) else {
            NSSound.beep()
            return
        }
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = NSApp.keyWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    /// File ▸ Page Setup… — paper size, orientation and margins for both
    /// printing and PDF export.
    static func pageSetup() {
        NSPageLayout().runModal(with: NSPrintInfo.shared)
    }
}

/// Which document model each window shows, so commands can act on the
/// front window without depending on where keyboard focus happens to be
/// (focused values are nil when focus is in the sidebar or a panel).
enum WindowDocuments {
    private static let table = NSMapTable<NSWindow, KishoDocumentModel>(keyOptions: .weakMemory, valueOptions: .weakMemory)

    static func register(_ model: KishoDocumentModel, for window: NSWindow) {
        table.setObject(model, forKey: window)
    }

    /// The model in the key (or main) window.
    static var front: KishoDocumentModel? {
        if let window = NSApp.keyWindow, let model = table.object(forKey: window) { return model }
        if let window = NSApp.mainWindow, let model = table.object(forKey: window) { return model }
        return nil
    }
}

/// Invisible view that registers its document model with the window it ends
/// up in. Dropped into the document view's background.
struct WindowDocumentRegistrar: NSViewRepresentable {
    let model: KishoDocumentModel

    func makeNSView(context: Context) -> RegistrarView {
        let view = RegistrarView()
        view.model = model
        return view
    }

    func updateNSView(_ view: RegistrarView, context: Context) {
        view.model = model
        if let window = view.window { WindowDocuments.register(model, for: window) }
    }

    final class RegistrarView: NSView {
        var model: KishoDocumentModel?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window, let model { WindowDocuments.register(model, for: window) }
        }
        override var isHidden: Bool { get { true } set {} }
    }
}

/// File ▸ Page Setup… and Print…, replacing SwiftUI's placeholders. Acts on
/// the front window's document whatever has keyboard focus.
struct PrintCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Page Setup…") { Printer.pageSetup() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Print…") {
                guard let model = WindowDocuments.front else { NSSound.beep(); return }
                Printer.printDocument(model, title: Exporter.keyWindowDocumentTitle)
            }
            .keyboardShortcut("p", modifiers: .command)
        }
    }
}
