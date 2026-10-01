//
//  Exporter.swift
//  Kisho
//
//  Created by Peter Macdonald on 05/06/2025.
//
import Foundation
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import UniformTypeIdentifiers
import SwiftUI

struct Exporter {
    // MARK: –– Plain Text Export

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

        // Section titles, and a default for body text in case a section has none.
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.boldSystemFont(ofSize: 18),
            .foregroundColor: PlatformColor.black
        ]

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
        output.addAttribute(.foregroundColor, value: PlatformColor.black, range: NSRange(location: 0, length: output.length))
        return output
    }
}

extension Exporter {
    enum Format: String, CaseIterable, Identifiable {
        case plainText, markdown, opml, docx, pdf, html
        var id: String { rawValue }
        var title: String {
            switch self {
            case .plainText: return "Plain Text"
            case .markdown: return "Markdown"
            case .opml: return "OPML"
            case .docx: return "Word"
            case .pdf: return "PDF"
            case .html: return "HTML"
            }
        }
        var fileExtension: String {
            switch self {
            case .plainText: return "txt"
            case .markdown: return "md"
            case .opml: return "opml"
            case .docx: return "docx"
            case .pdf: return "pdf"
            case .html: return "html"
            }
        }
    }

    /// The document converted to `format`, or nil when the conversion fails.
    /// `title` names the document in formats that carry a title (OPML, the
    /// PDF footer). `pageOptions` is the paper for the PDF; the default is
    /// the user's Page Setup paper on the Mac and A4/Letter by locale on iOS.
    static func data(for document: KishoDocumentModel, as format: Format, title: String,
                     pageOptions: PageLayout.Options? = nil) -> Data? {
        switch format {
        case .plainText:
            return Data(plainText(from: document.sections).utf8)
        case .markdown:
            return Data(Markdown.string(from: document.sections, typography: document.typography).utf8)
        case .opml:
            return Data(OPML.string(from: document.sections, title: title).utf8)
        case .docx:
            return Docx.data(from: document.sections, typography: document.typography)
        case .pdf:
            // Same pages as File ▸ Print: the user's paper and margins, page numbers,
            // headings kept with their text.
            return PageLayout.pdfData(from: document.sections, options: pageOptions ?? .standard(title: title))
        case .html:
            return Data(htmlString(from: document.sections).utf8)
        }
    }
}

#if os(macOS)
extension Exporter {
    /// Export the document in `format`, asking where to save. `title` is the
    /// suggested file name (usually the document's name).
    static func export(_ document: KishoDocumentModel, as format: Format, title: String) {
        guard let data = data(for: document, as: format, title: title) else {
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
