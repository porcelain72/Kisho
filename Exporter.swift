//
//  Exporter.swift
//  Kisho
//
//  Created by Peter Macdonald on 05/06/2025.
//
import Foundation
#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

import PDFKit // for PDF generation
import UniformTypeIdentifiers
import SwiftUI

struct Exporter {
    // MARK: –– Plain Text Export

    static let defaultInsets : EdgeInsets = EdgeInsets(top: 40.0, leading: 40.0, bottom: 40.0, trailing: 40.0)
    
    /// Recursively collects every section’s plain‐text (title + body) in a depth‐first order.
    static func plainText(from sections: [KishoSection]) -> String {
        var result = ""
        for section in sections {
            // 1) Section Title
            result += section.displayTitle + "\n\n"

            // 2) Section Body (strip all attributes)
            let body = section.content.attributedString.string.trimmingCharacters(in: .newlines)
            result += body + "\n\n"

            // 3) Recurse into children
            if !section.children.isEmpty {
                result += plainText(from: section.children)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: –– Attributed Text Export (for PDF, HTML, etc.)

    /// Recursively concatenates every section’s attributed content, inserting headings as larger fonts.
    /// You can adjust “titleAttributes” as desired—for example, make titles bold or larger.
    static func attributedText(from sections: [KishoSection]) -> NSAttributedString {
        let output = NSMutableAttributedString()

        #if os(macOS)
        // Define a default attribute for section titles:
        let titleFont = NSFont.boldSystemFont(ofSize: 18)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.black
        ]

        // A default attribute for section body text (in case the section has no body):
        let defaultBodyFont = NSFont.systemFont(ofSize: 12)
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: defaultBodyFont,
            .foregroundColor: NSColor.labelColor
        ]
        #else
        // Define a default attribute for section titles:
        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]

        // A default attribute for section body text (in case the section has no body):
        let defaultBodyFont = UIFont.systemFont(ofSize: 12)
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: defaultBodyFont,
            .foregroundColor: UIColor.black
        ]
        #endif
        
        func appendSections(_ list: [KishoSection], indentLevel: Int = 0) {
            for section in list {
                // 1) Title
                let titleString = section.displayTitle + "\n"
                let indentedTitle = String(repeating: "    ", count: indentLevel) + titleString
                let titleAttrString = NSAttributedString(string: indentedTitle, attributes: titleAttrs)
                output.append(titleAttrString)

                // 2) Body
                let bodyAttrString = section.content.attributedString
                // Optionally, indent the body lines too:
                if indentLevel > 0 {
                    let mutableBody = NSMutableAttributedString(attributedString: bodyAttrString)
                    let fullRange = NSRange(location: 0, length: mutableBody.length)
                    mutableBody.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { (value, range, stop) in
                        let para = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                            ?? NSMutableParagraphStyle()
                        para.firstLineHeadIndent = CGFloat(indentLevel) * 20
                        para.headIndent = CGFloat(indentLevel) * 20
                        mutableBody.addAttribute(.paragraphStyle, value: para, range: range)
                    }
                    output.append(mutableBody)
                } else {
                    // Top‐level always uses the raw attributed string:
                    output.append(bodyAttrString)
                }
                output.append(NSAttributedString(string: "\n\n"))

                // 3) Children (increase indent if you want numbered hierarchy)
                if !section.children.isEmpty {
                    appendSections(section.children, indentLevel: indentLevel + 1)
                }
            }
        }

        appendSections(sections)

        // Exports are for paper/other apps, so bake in a real black rather than
        // the appearance-adaptive label colour, which renders white when the
        // app is in dark mode.
        #if os(macOS)
        let exportColor = NSColor.black
        #else
        let exportColor = UIColor.black
        #endif
        output.addAttribute(.foregroundColor, value: exportColor, range: NSRange(location: 0, length: output.length))
        return output
    }

  
        /// Renders the given `NSAttributedString` into a multi‐page PDF `Data`.
        /// Each page is `pageSize` points (default: 612×792 = U.S. Letter).
        static func pdfData(
            from attributed: NSAttributedString,
            pageSize: CGSize = CGSize(width: 612, height: 792)
        ) -> Data? {
            // 1) Build the text storage / layout manager
            let textStorage = NSTextStorage(attributedString: attributed)
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)

            // 2) We will keep track of which glyph ranges go on each page
            var pageGlyphRanges: [NSRange] = []

            // 3) Add one NSTextContainer per page until we've covered all glyphs
            while true {
                let textContainer = NSTextContainer(size: pageSize.inset(by: self.defaultInsets))
                // Remove side‐padding so text truly fills the page width
                textContainer.lineFragmentPadding = 0
                layoutManager.addTextContainer(textContainer)

                // Force the layout manager to layout *all* glyphs up through this new container:
                let glyphRangeInContainer = layoutManager.glyphRange(for: textContainer)
                // By converting to character range and back, we force a full layout pass
                let _ = layoutManager.characterRange(
                    forGlyphRange: glyphRangeInContainer,
                    actualGlyphRange: nil
                )

                // Now ask “which glyphs ended up in this container?”
                let finalGlyphRange = layoutManager.glyphRange(for: textContainer)
                pageGlyphRanges.append(finalGlyphRange)

                // If that range reaches the end of the document’s glyphs, stop.
                // Also stop if a page took no glyphs at all (e.g. an oversized
                // attachment), otherwise this would loop forever.
                if NSMaxRange(finalGlyphRange) >= layoutManager.numberOfGlyphs
                    || finalGlyphRange.length == 0 {
                    break
                }
                // Otherwise, loop again to add another page/container
            }

            // 4) Create a PDF context that can hold multiple pages
            let pdfData = NSMutableData()
            guard
                let consumer = CGDataConsumer(data: pdfData as CFMutableData)
            else {
                return nil
            }
            var mediaBox = CGRect(origin: .zero, size: pageSize)
            guard let pContext = CGContext(
                consumer: consumer,
                mediaBox: &mediaBox,
                nil
            ) else {
                return nil
            }
            #if os(macOS)
            let nsgc = NSGraphicsContext(cgContext: pContext, flipped: true)
            NSGraphicsContext.current = nsgc
           
            
            let pdfContext = nsgc.cgContext
#else
           UIGraphicsBeginPDFContextToData(pdfData, mediaBox, nil)
            guard let pdfContext = UIGraphicsGetCurrentContext() else { return nil}
            #endif
            // 5) Draw each page in turn
            for pageIndex in 0 ..< pageGlyphRanges.count {
                let glyphRange = pageGlyphRanges[pageIndex]
                let textContainers = layoutManager.textContainers

                guard pageIndex < textContainers.count else { continue }
                let container = textContainers[pageIndex]

                #if os(macOS)
                pdfContext.beginPDFPage(nil)
                #else
                UIGraphicsBeginPDFPage()

                #endif
                // Flip coordinates so origin is top‐left
                pdfContext.saveGState()
                pdfContext.translateBy(x: defaultInsets.leading, y: pageSize.height - defaultInsets.bottom)
                pdfContext.scaleBy(x: 1.0, y: -1.0)

                // Draw the background (underlines, attachments, etc.)
                layoutManager.drawBackground(
                    forGlyphRange: glyphRange,
                    at: .zero
                )
                // Draw the glyphs themselves
                layoutManager.drawGlyphs(
                    forGlyphRange: glyphRange,
                    at: .zero
                )

                pdfContext.restoreGState()
                pdfContext.endPDFPage()
            }

            pdfContext.closePDF()
            return pdfData as Data
        }
    
    /// Renders the given `NSAttributedString` into a single‐page (or multipage) PDF `Data`.
   

    // (Later, you can add an HTML conversion method, e.g. `static func htmlString(from:) -> String`)
}

#if os(macOS)
extension Exporter {
    enum Format: String, CaseIterable, Identifiable {
        case plainText, markdown, docx, pdf, html
        var id: String { rawValue }
        var title: String {
            switch self {
            case .plainText: return "Plain Text"
            case .markdown: return "Markdown"
            case .docx: return "Word"
            case .pdf: return "PDF"
            case .html: return "HTML"
            }
        }
        var fileExtension: String {
            switch self {
            case .plainText: return "txt"
            case .markdown: return "md"
            case .docx: return "docx"
            case .pdf: return "pdf"
            case .html: return "html"
            }
        }
    }

    /// Export the document in `format`, asking where to save. `title` is the
    /// suggested file name (usually the document's name).
    static func export(_ document: KishoDocumentModel, as format: Format, title: String) {
        let data: Data?
        switch format {
        case .plainText:
            data = Data(plainText(from: document.sections).utf8)
        case .markdown:
            data = Data(Markdown.string(from: document.sections, typography: document.typography).utf8)
        case .docx:
            data = Docx.data(from: document.sections, typography: document.typography)
        case .pdf:
            // Same pages as File ▸ Print: the user's paper and margins, page numbers,
            // headings kept with their text.
            data = PageLayout.pdfData(from: document.sections, options: .fromPrintInfo(title: title))
        case .html:
            data = Data(htmlString(from: document.sections).utf8)
        }
        guard let data else {
            let alert = NSAlert()
            alert.messageText = "Export failed"
            alert.informativeText = "The document could not be converted to \(format.title)."
            alert.runModal()
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(title).\(format.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension)].compactMap { $0 }
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// The name of the document in the key window, for a default file name.
    static var keyWindowDocumentTitle: String {
        if let url = NSApp.keyWindow?.representedURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return NSApp.keyWindow?.title.isEmpty == false ? NSApp.keyWindow!.title : "Untitled"
    }
}
#endif

extension Exporter {
    static func htmlString(from sections: [KishoSection]) -> String {
        var html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\n"
        func recurse(_ list: [KishoSection], level: Int) {
            let tag = "h\(min(level, 6))"
            for section in list {
                html += "<\(tag)>\(section.displayTitle.htmlEscaped())</\(tag)>\n"
                let bodyHTML = rtfToHTML(section.content.attributedString)
                html += bodyHTML + "\n"
                if !section.children.isEmpty {
                    recurse(section.children, level: level + 1)
                }
            }
        }
        recurse(sections, level: 1)
        html += "</body></html>"
        return html
    }
    // You may implement `rtfToHTML(_:)` by exporting RTF to HTML via NSAttributedString APIs.
    private static func rtfToHTML(_ attributed: NSAttributedString) -> String {
        guard let data = try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        ) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }
}


extension String {
    /// Returns a new string in which the characters &, <, >, ", and ' have been
    /// replaced by their corresponding HTML entities.
    ///
    /// Example:
    ///     let raw = "5 > 3 & 2 < 4"
    ///     print(raw.htmlEscaped())
    ///     // prints: 5 &gt; 3 &amp; 2 &lt; 4
    ///
    func htmlEscaped() -> String {
        var result = ""
        result.reserveCapacity(count)

        for character in self {
            switch character {
            case "&":
                result += "&amp;"
            case "<":
                result += "&lt;"
            case ">":
                result += "&gt;"
            case "\"":
                result += "&quot;"
            case "'":
                result += "&#39;"
            default:
                result.append(character)
            }
        }
        return result
    }
}

extension CGSize {
    
    func inset(by insets:EdgeInsets) -> CGSize {
        
        return CGSize(width: self.width - insets.leading - insets.trailing, height: self.height - insets.top - insets.bottom)
    }
}
