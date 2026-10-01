//
//  KishoOPML.swift
//  Kisho
//
//  OPML import and export — the interchange format of outliners
//  (OmniOutliner, Dynalist, Workflowy, Bike, mind-map tools). Every
//  <outline> is a block: `text` is the title, `_note` (the de-facto
//  convention for body text) is the body, `category` (OPML 2.0) carries
//  tags, nesting is nesting.
//

import Foundation
import AppKit
import RichTextEditor

enum OPML {

    // MARK: Export

    static func string(from sections: [KishoSection], title: String) -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
        <head><title>\(escape(title))</title></head>
        <body>

        """
        func walk(_ list: [KishoSection], indent: Int) {
            let pad = String(repeating: "  ", count: indent)
            for section in list {
                var attributes = " text=\"\(escape(section.displayTitle))\""
                let note = section.content.attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty { attributes += " _note=\"\(escape(note))\"" }
                if !section.tags.isEmpty { attributes += " category=\"\(escape(section.tags.joined(separator: ",")))\"" }
                // Planning metadata: `_status="checked"` is the outliner convention
                // for done; the rest ride along as kisho-prefixed attributes.
                if section.status == .done { attributes += " _status=\"checked\"" }
                if let status = section.status { attributes += " kisho_status=\"\(status.rawValue)\"" }
                if let colour = section.colorIndex { attributes += " kisho_colour=\"\(colour)\"" }
                if !section.synopsis.isEmpty { attributes += " kisho_synopsis=\"\(escape(section.synopsis))\"" }
                if section.children.isEmpty {
                    out += "\(pad)<outline\(attributes)/>\n"
                } else {
                    out += "\(pad)<outline\(attributes)>\n"
                    walk(section.children, indent: indent + 1)
                    out += "\(pad)</outline>\n"
                }
            }
        }
        walk(sections, indent: 1)
        out += "</body>\n</opml>\n"
        return out
    }

    /// Attribute-value escaping; newlines become &#10; so notes survive as one attribute.
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\n": out += "&#10;"
            case "\r": continue
            case "\t": out.unicodeScalars.append(scalar)
            case _ where scalar.value < 0x20: continue
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    // MARK: Import

    enum ImportError: LocalizedError {
        case notOPML
        case malformed(String)
        var errorDescription: String? {
            switch self {
            case .notOPML: return "This file isn't an OPML outline."
            case .malformed(let detail): return "The OPML file couldn't be read: \(detail)"
            }
        }
    }

    /// Blocks from OPML data. Throws if the XML is malformed or has no <opml> root.
    static func sections(from data: Data, typography: TypographySettings = TypographySettings()) throws -> [KishoSection] {
        let parser = XMLParser(data: data)
        let delegate = Delegate(baseFont: typography.baseFont)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw ImportError.malformed(parser.parserError?.localizedDescription ?? "unknown error")
        }
        guard delegate.sawOPML else { throw ImportError.notOPML }
        return delegate.roots.isEmpty ? [KishoSection(title: KishoSection.defaultTitle)] : delegate.roots
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let baseFont: NSFont
        var roots: [KishoSection] = []
        private var stack: [KishoSection] = []
        var sawOPML = false
        private var inBody = false

        init(baseFont: NSFont) { self.baseFont = baseFont }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            switch name.lowercased() {
            case "opml": sawOPML = true
            case "body": inBody = true
            case "outline" where inBody:
                let title = (attributes["text"] ?? attributes["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let section = KishoSection(title: title.isEmpty ? KishoSection.defaultTitle : title)
                if let note = attributes["_note"], !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    section.content.attributedString = OPML.body(note, baseFont: baseFont)
                }
                if let category = attributes["category"] {
                    section.tags = category.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                if let raw = attributes["kisho_status"], let status = BlockStatus(rawValue: raw.lowercased()) {
                    section.status = status
                } else if attributes["_status"]?.lowercased() == "checked" || attributes["_complete"]?.lowercased() == "true" {
                    section.status = .done
                }
                if let colour = attributes["kisho_colour"].flatMap(Int.init), BlockPalette.isValid(colour) {
                    section.colorIndex = colour
                }
                if let synopsis = attributes["kisho_synopsis"], !synopsis.isEmpty { section.synopsis = synopsis }
                if let parent = stack.last { parent.children.append(section) } else { roots.append(section) }
                stack.append(section)
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name.lowercased() {
            case "body": inBody = false
            case "outline" where inBody && !stack.isEmpty: stack.removeLast()
            default: break
            }
        }
    }

    /// Note text as body paragraphs (line breaks kept as paragraph breaks,
    /// runs of blank lines collapsed).
    static func body(_ note: String, baseFont: NSFont) -> NSAttributedString {
        let lines = note.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return NSAttributedString(string: lines.joined(separator: "\n"),
                                  attributes: [.font: baseFont, .foregroundColor: NSColor.labelColor])
    }
}

#if os(macOS)
import UniformTypeIdentifiers

extension UTType {
    static let opml = UTType(importedAs: "org.opml.opml", conformingTo: .xml)
}

/// Shared "import a file as a new untitled document" flow used by the
/// Markdown and OPML importers.
enum DocumentImport {
    static func run(allowedTypes: [UTType], message: String,
                    parse: @escaping (URL) throws -> (sections: [KishoSection], typography: TypographySettings)) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = message
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let imported = try parse(url)
                let model = KishoDocumentModel(sections: imported.sections)
                model.typography = imported.typography
                KishoDocument.pendingImport = model
                NSDocumentController.shared.newDocument(nil)
                // The new window is key by the time this runs. Mark it edited so
                // closing it asks about saving and the import can't be lost silently.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if let document = NSApp.keyWindow?.windowController?.document as? NSDocument,
                       document.fileURL == nil {
                        document.updateChangeCount(.changeDone)
                    }
                }
            } catch {
                KishoDocument.pendingImport = nil
                NSAlert(error: error).runModal()
            }
        }
    }
}

extension OPML {
    /// File ▸ Import OPML…
    static func importIntoNewDocument() {
        DocumentImport.run(
            allowedTypes: [.opml, .xml],
            message: "Choose an OPML outline. Each item becomes a block in a new document; notes become body text."
        ) { url in
            let typography = KishoPreferences.defaultTypography
            return (try sections(from: Data(contentsOf: url), typography: typography), typography)
        }
    }
}
#endif
