//
//  KishoLocalization.swift
//  Kisho
//
//  User-facing count strings. Each key has plural variants in
//  Localizable.xcstrings; `localizedStringWithFormat` picks the right one and
//  writes the number with the locale's grouping separators ("1,250 words").
//  Plain `Text("\(n) words")` would do neither reliably, so counts shown in
//  the UI go through here and are rendered with `Text(verbatim:)`.
//  `NSLocalizedString` (not `String(localized:)`) fetches the bare pattern,
//  because the latter would try to format the `%lld` with no argument.
//

import Foundation

enum KishoCounts {
    static func words(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("%lld words", comment: "Word count for a block or document, e.g. '1,250 words'"),
            count)
    }

    static func blocks(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("%lld blocks", comment: "Number of blocks in a document, e.g. '12 blocks'"),
            count)
    }

    static func subBlocks(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("%lld sub-blocks", comment: "Number of blocks nested inside a block, e.g. '3 sub-blocks'"),
            count)
    }

    static func matches(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("%lld matches", comment: "Number of find results, e.g. '4 matches'"),
            count)
    }

    /// "3 of 12": the current item's position in a sequence (find results,
    /// printed pages).
    static func position(_ index: Int, of total: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("%1$lld of %2$lld", comment: "Position in a sequence: current item number, then total (find results, page numbers)"),
            index, total)
    }
}
