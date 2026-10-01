//
//  KishoDocx.swift
//  Kisho
//
//  Word (.docx) export. A .docx is a zip of XML parts; this writes the six
//  parts Word needs and packs them with a minimal, store-only zip writer, so
//  block titles come out as real Word heading styles (Heading 1–6, visible in
//  Word's navigation pane and outline view) and body runs keep bold/italic/underline.
//  The attributed-string→OOXML path in AppKit would only give sized bold
//  text, not styles, which is why this is hand-rolled.
//

import Foundation
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import RichTextEditor

enum Docx {

    // MARK: - Public

    /// The complete .docx file.
    static func data(from sections: [KishoSection], typography: TypographySettings) -> Data {
        var zip = ZipWriter()
        zip.add(path: "[Content_Types].xml", text: contentTypesXML)
        zip.add(path: "_rels/.rels", text: relsXML)
        zip.add(path: "word/_rels/document.xml.rels", text: documentRelsXML)
        zip.add(path: "word/document.xml", text: documentXML(sections: sections))
        zip.add(path: "word/styles.xml", text: stylesXML(typography: typography))
        zip.add(path: "word/settings.xml", text: settingsXML)
        return zip.finish()
    }

    // MARK: - Parts

    static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
    <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
    </Types>
    """

    static let relsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    /// Word finds the styles part through this relationship, not by content
    /// type; without it every paragraph falls back to Normal.
    static let documentRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
    </Relationships>
    """

    /// Document settings. The spec's default tab stop is ½ inch (720 twips)
    /// when unstated, but Pages only lays tabs out to stops when the setting
    /// is explicit.
    static let settingsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:defaultTabStop w:val="720"/>
    <w:characterSpacingControl w:val="doNotCompress"/>
    </w:settings>
    """

    private static let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    /// Body: a heading paragraph per block (style by depth) followed by one
    /// paragraph per body line, with bold/italic runs.
    static func documentXML(sections: [KishoSection]) -> String {
        var body = ""
        func walk(_ list: [KishoSection], depth: Int) {
            for section in list {
                body += "<w:p><w:pPr><w:pStyle w:val=\"Heading\(min(depth, 6))\"/></w:pPr>"
                body += run(escape(section.displayTitle), bold: false, italic: false)
                body += "</w:p>\n"
                for paragraph in paragraphs(section.content.attributedString) {
                    body += "<w:p>" + paragraph + "</w:p>\n"
                }
                walk(section.children, depth: depth + 1)
            }
        }
        walk(sections, depth: 1)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="\(w)">
        <w:body>
        \(body)<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>
        </w:body>
        </w:document>
        """
    }

    /// Normal + Heading 1–6. Sizes are half-points. The body font is the
    /// document's typography; headings use the same family, bold, stepping
    /// down in size, with an outline level so Word treats them as headings.
    static func stylesXML(typography: TypographySettings) -> String {
        let family = escape(wordFontFamily(typography.fontFamily))
        let bodyHalfPoints = Int((typography.fontSize * 2).rounded())
        let headingPoints = [24, 20, 17, 15, 14, 13]

        var styles = """
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
        <w:name w:val="Normal"/><w:qFormat/>
        <w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr>
        <w:rPr><w:rFonts w:ascii="\(family)" w:hAnsi="\(family)" w:cs="\(family)"/><w:sz w:val="\(bodyHalfPoints)"/><w:szCs w:val="\(bodyHalfPoints)"/></w:rPr>
        </w:style>

        """
        for (i, points) in headingPoints.enumerated() {
            let level = i + 1
            styles += """
            <w:style w:type="paragraph" w:styleId="Heading\(level)">
            <w:name w:val="heading \(level)"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
            <w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="\(level == 1 ? 480 : 320)" w:after="120"/><w:outlineLvl w:val="\(level - 1)"/></w:pPr>
            <w:rPr><w:b/><w:bCs/><w:sz w:val="\(points * 2)"/><w:szCs w:val="\(points * 2)"/></w:rPr>
            </w:style>

            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="\(w)">
        <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="\(family)" w:hAnsi="\(family)" w:cs="\(family)"/><w:sz w:val="\(bodyHalfPoints)"/><w:szCs w:val="\(bodyHalfPoints)"/><w:lang w:val="en-GB"/></w:rPr></w:rPrDefault><w:pPrDefault/></w:docDefaults>
        \(styles)</w:styles>
        """
    }

    /// Word has no ".AppleSystemUIFont"; map the system font to a face Word ships.
    static func wordFontFamily(_ family: String) -> String {
        family.hasPrefix(".") ? "Helvetica Neue" : family
    }

    // MARK: - Runs

    /// One entry per non-empty line of the body, each the inner XML of a `w:p`.
    static func paragraphs(_ text: NSAttributedString) -> [String] {
        var result: [String] = []
        let full = text.string as NSString
        var location = 0
        while location < full.length {
            let lineRange = full.lineRange(for: NSRange(location: location, length: 0))
            var content = lineRange
            while content.length > 0,
                  let scalar = Unicode.Scalar(full.character(at: NSMaxRange(content) - 1)),
                  CharacterSet.newlines.contains(scalar) {
                content.length -= 1
            }
            if content.length > 0 {
                let runs = runsXML(text.attributedSubstring(from: content))
                if !runs.isEmpty { result.append(runs) }
            }
            location = NSMaxRange(lineRange)
        }
        return result
    }

    /// Runs for one paragraph, split where bold/italic/underline changes.
    static func runsXML(_ text: NSAttributedString) -> String {
        var out = ""
        var pending: (text: String, bold: Bool, italic: Bool, underline: Bool)?
        func flush() {
            if let p = pending, !p.text.isEmpty {
                out += run(escape(p.text), bold: p.bold, italic: p.italic, underline: p.underline)
            }
            pending = nil
        }
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            let font = attrs[.font] as? PlatformFont
            let bold = font?.isBoldTrait ?? false, italic = font?.isItalicTrait ?? false
            let underline = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            let piece = (text.string as NSString).substring(with: range)
            if let p = pending, p.bold == bold, p.italic == italic, p.underline == underline {
                pending?.text += piece
            } else {
                flush()
                pending = (piece, bold, italic, underline)
            }
        }
        flush()
        return out
    }

    private static func run(_ escapedText: String, bold: Bool, italic: Bool, underline: Bool = false) -> String {
        var rPr = ""
        if bold { rPr += "<w:b/><w:bCs/>" }
        if italic { rPr += "<w:i/><w:iCs/>" }
        if underline { rPr += "<w:u w:val=\"single\"/>" }
        let props = rPr.isEmpty ? "" : "<w:rPr>\(rPr)</w:rPr>"
        // Tabs become Word tabs; other control characters would make the XML invalid.
        let parts = escapedText.components(separatedBy: "\t")
        var body = ""
        for (i, part) in parts.enumerated() {
            if i > 0 { body += "<w:tab/>" }
            if !part.isEmpty { body += "<w:t xml:space=\"preserve\">\(part)</w:t>" }
        }
        return "<w:r>\(props)\(body)</w:r>"
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\t", "\n", "\r": out.unicodeScalars.append(scalar)
            case _ where scalar.value < 0x20: continue   // invalid in XML 1.0
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

// MARK: - Minimal zip writer

/// Writes a zip archive with stored (uncompressed) entries — all a .docx
/// needs, and Word, Pages and LibreOffice all accept it. Text parts are small
/// enough that compression isn't worth a dependency.
struct ZipWriter {
    private struct Entry { let name: Data; let data: Data; let crc: UInt32; let offset: UInt32 }
    private var body = Data()
    private var entries: [Entry] = []

    mutating func add(path: String, text: String) {
        add(path: path, data: Data(text.utf8))
    }

    mutating func add(path: String, data: Data) {
        let name = Data(path.utf8)
        let crc = ZipWriter.crc32(data)
        let offset = UInt32(body.count)
        // Local file header.
        body.append(le32(0x04034b50))
        body.append(le16(20))            // version needed: 2.0
        body.append(le16(0x0800))        // flags: UTF-8 names
        body.append(le16(0))             // method: stored
        body.append(le16(0)); body.append(le16(0x21))   // time, date (fixed: 1980-01-01)
        body.append(le32(crc))
        body.append(le32(UInt32(data.count)))
        body.append(le32(UInt32(data.count)))
        body.append(le16(UInt16(name.count)))
        body.append(le16(0))             // extra length
        body.append(name)
        body.append(data)
        entries.append(Entry(name: name, data: data, crc: crc, offset: offset))
    }

    func finish() -> Data {
        var out = body
        let centralStart = UInt32(out.count)
        for e in entries {
            out.append(le32(0x02014b50))
            out.append(le16(20)); out.append(le16(20))  // made by, needed
            out.append(le16(0x0800))
            out.append(le16(0))
            out.append(le16(0)); out.append(le16(0x21))
            out.append(le32(e.crc))
            out.append(le32(UInt32(e.data.count)))
            out.append(le32(UInt32(e.data.count)))
            out.append(le16(UInt16(e.name.count)))
            out.append(le16(0)); out.append(le16(0))     // extra, comment
            out.append(le16(0)); out.append(le16(0))     // disk, internal attrs
            out.append(le32(0))                          // external attrs
            out.append(le32(e.offset))
            out.append(e.name)
        }
        let centralSize = UInt32(out.count) - centralStart
        out.append(le32(0x06054b50))
        out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(entries.count))); out.append(le16(UInt16(entries.count)))
        out.append(le32(centralSize))
        out.append(le32(centralStart))
        out.append(le16(0))
        return out
    }

    private func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in data {
            c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFFFFFF
    }
}
