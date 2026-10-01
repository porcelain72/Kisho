//
//  KishSidebarOutlineView.swift
//  Kisho
//
//  Created by Peter Macdonald on 30/05/2025.
//

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// The Mac sidebar: tag filter, the outline, word/block totals. The iOS
/// outline is its own view (Phase C of the iOS plan).
struct KishoSidebarOutlineView: View {
    @EnvironmentObject var document : KishoDocumentModel
    @Binding var showDeleteAlert : Bool

    var body: some View {
        VStack(spacing: 0) {
            TagFilterBar()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(document.sections) { section in
                            SectionRow(section: section, depth: 0)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: document.selectedSectionID) { newID in
                    guard let newID else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newID)
                    }
                }
            }

            Divider()
            DocumentStatsFooter(stats: document.stats)
        }
    }
}

/// Word/block totals. Observes the model's lightweight `stats` signal so it
/// refreshes on every keystroke without re-rendering the outline.
private struct DocumentStatsFooter: View {
    @EnvironmentObject var document: KishoDocumentModel
    @ObservedObject var stats: KishoDocumentModel.Stats

    var body: some View {
        HStack {
            Text("\(document.totalWordCount.formatted()) words")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(document.orderedSections.count) blocks")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// Picker above the outline that narrows the rows to blocks carrying a tag.
private struct TagFilterBar: View {
    @EnvironmentObject var document: KishoDocumentModel

    var body: some View {
        let tags = document.allTags
        if !tags.isEmpty || document.tagFilter != nil {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                Picker("Tag filter", selection: $document.tagFilter) {
                    Text("All blocks").tag(String?.none)
                    ForEach(tags, id: \.self) { tag in
                        Text(tag).tag(String?.some(tag))
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                if document.tagFilter != nil {
                    Button { document.tagFilter = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear filter")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .onChange(of: tags) { newTags in
                // A filter for a tag that no longer exists anywhere is cleared.
                if let f = document.tagFilter, !newTags.contains(f) { document.tagFilter = nil }
            }
        }
    }
}
#endif
