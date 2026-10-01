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

    var body: some View {
        NavigationStack {
            List(document.sections, children: \.childrenOrNil) { section in
                NavigationLink(value: section.id) {
                    SectionListRow(section: section)
                }
            }
            .listStyle(.plain)
            .navigationTitle(fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                if let section = document.section(withID: id) {
                    SectionReadingView(section: section)
                }
            }
            .overlay {
                if document.sections.isEmpty {
                    ContentUnavailableView("No Blocks", systemImage: "square.stack.3d.up",
                                           description: Text("This document has no blocks yet."))
                }
            }
        }
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
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension KishoSection {
    /// `List(_:children:)` wants nil, not an empty array, for a leaf.
    var childrenOrNil: [KishoSection]? { children.isEmpty ? nil : children }
}
#endif
