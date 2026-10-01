//
//  KishoSection+Snapshot.swift
//  Kisho
//
//  Whole-tree text snapshots (for undo of document-wide changes such as
//  typography) and the paragraph split behind "Split Paragraphs into
//  Blocks". Foundation only, so it compiles for every platform.
//

import Foundation
import RichTextEditor

struct SubtreeSnapshot {
    struct SectionState {
        var title: String
        var content: RichTextModel
    }

    var states: [UUID: SectionState]
}

extension KishoSection {

    // MARK: - Snapshots

    static func documentSnapshot(of sections: [KishoSection]) -> SubtreeSnapshot {
        var states: [UUID: SubtreeSnapshot.SectionState] = [:]
        func collect(_ section: KishoSection) {
            states[section.id] = SubtreeSnapshot.SectionState(
                title: section.title,
                content: section.content.copy()
            )
            section.children.forEach(collect)
        }
        sections.forEach(collect)
        return SubtreeSnapshot(states: states)
    }

    static func applyDocumentSnapshot(_ snapshot: SubtreeSnapshot, to sections: [KishoSection]) {
        func apply(_ section: KishoSection) {
            if let state = snapshot.states[section.id] {
                section.title = state.title
                section.content.attributedString = state.content.attributedString
            }
            section.children.forEach(apply)
            section.modifiedAt = Date()
        }
        sections.forEach(apply)
    }

    // MARK: - Split

    /// Paragraphs that Split should turn into child sections: any extra
    /// lines typed into the title, then the body, one paragraph per line.
    static func paragraphModelsForSplit(section: KishoSection) -> [RichTextModel] {
        let merged = NSMutableAttributedString()

        let extraTitleLines = section.title
            .components(separatedBy: .newlines)
            .dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !extraTitleLines.isEmpty {
            merged.append(NSAttributedString(string: extraTitleLines + "\n"))
        }

        merged.append(section.content.attributedString)

        return splitParagraphs(from: merged)
    }

    static func splitParagraphs(from source: NSAttributedString) -> [RichTextModel] {
        let ns = source.string as NSString
        var parts: [RichTextModel] = []
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: .byLines
        ) { _, substringRange, _, _ in
            guard substringRange.length > 0 else { return }
            let sub = source.attributedSubstring(from: substringRange)
            let trimmed = sub.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let model = RichTextModel()
            model.attributedString = sub
            parts.append(model)
        }
        return parts
    }

    /// Every section in the tree, in reading order.
    static func allSections(in sections: [KishoSection]) -> [KishoSection] {
        var result: [KishoSection] = []
        func collect(_ section: KishoSection) {
            result.append(section)
            section.children.forEach(collect)
        }
        sections.forEach(collect)
        return result
    }
}
