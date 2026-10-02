//
//  KishoDocumentView+iOS.swift
//  Kisho
//
//  Phase A placeholder for the iOS document window: the outline as a list
//  and the selected block's text, read-only. Enough to prove the model,
//  file format and exporters build and run on iOS; Phases B–D replace it
//  with the card editor, structure editing and the rest.
//

#if os(iOS)
import SwiftUI

struct KishoDocumentView: View {
    let fileURL: URL?
    @EnvironmentObject var document: KishoDocumentModel
    @State private var selectedID: UUID?

    // DocumentGroup already wraps the content in a navigation bar (title and
    // Done/back), so no NavigationStack here: the outline and the selected
    // block's text share the screen instead.
    var body: some View {
        VStack(spacing: 0) {
            List(document.sections, children: \.childrenOrNil, selection: $selectedID) { section in
                SectionListRow(section: section)
                    .tag(section.id)
            }
            .listStyle(.plain)
            .overlay {
                if document.sections.isEmpty {
                    ContentUnavailableView("No Blocks", systemImage: "square.stack.3d.up",
                                           description: Text("This document has no blocks yet."))
                }
            }

            Divider()

            if let id = selectedID, let section = document.section(withID: id) {
                SectionReadingView(section: section)
                    .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView("No Block Selected", systemImage: "text.alignleft",
                                       description: Text("Choose a block above to read it."))
                    .frame(maxHeight: .infinity)
            }
        }
        .onAppear { selectedID = document.selectedSectionID ?? document.sections.first?.id }
    }
}

private struct SectionListRow: View {
    @ObservedObject var section: KishoSection

    var body: some View {
        HStack(spacing: 8) {
            if let colour = section.colorIndex {
                Circle().fill(BlockPalette.color(colour)).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(section.displayTitle).lineLimit(1)
                if !section.synopsis.isEmpty {
                    Text(section.synopsis).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if let status = section.status {
                Image(systemName: status.symbol)
                    .font(.caption)
                    .foregroundStyle(status == .done ? Color.green : Color.secondary)
            }
            let words = section.totalWordCount
            if words > 0 {
                Text("\(words)").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

private struct SectionReadingView: View {
    @ObservedObject var section: KishoSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(section.displayTitle)
                    .font(.title2.weight(.semibold))
                if !section.tags.isEmpty {
                    Text(section.tags.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(AttributedString(section.content.attributedString))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }
}

private extension KishoSection {
    /// `List(_:children:)` wants nil, not an empty array, for a leaf.
    var childrenOrNil: [KishoSection]? { children.isEmpty ? nil : children }
}
#endif
