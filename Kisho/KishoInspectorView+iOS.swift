//
//  KishoInspectorView+iOS.swift
//  Kisho
//
//  The inspector on iOS, shown as a sheet: the document's typography at
//  the top, then the selected block's status, colour, tags, synopsis and
//  notes. Same model calls as the Mac inspector, so every change is one
//  undo step and marks the document for saving.
//

#if os(iOS)
import SwiftUI

struct BlockInspectorSheet: View {
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.kishoEditorTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Inspector") { dismiss() }
            Form {
                DocumentInspectorSection()
                if let section = document.selectedSection {
                    BlockInspectorForm(section: section)
                        .id(section.id)   // fresh drafts per block
                } else {
                    Section {
                        Text("No block selected").foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(theme == .sepia ? .hidden : .automatic)
        }
        .themedPanel()
    }
}

/// Document-wide settings: the font family and size every block uses, and
/// the named presets.
private struct DocumentInspectorSection: View {
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.undoManager) private var environmentUndoManager
    @Environment(\.documentUndoManager) private var documentUndoManager
    private var undoManager: UndoManager? { documentUndoManager ?? environmentUndoManager }
    @State private var families: [String] = []

    private let sizes: [Double] = [10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 22, 24, 28]

    var body: some View {
        let typography = Binding<TypographySettings>(
            get: { document.typography },
            set: { document.setTypography($0, undoManager: undoManager) }
        )
        Section {
            Picker("Font", selection: typography.fontFamily) {
                ForEach(families, id: \.self) { family in
                    Text(TypographySettings.displayName(forFamily: family)).tag(family)
                }
            }
            Picker("Size", selection: typography.fontSize) {
                ForEach(sizes, id: \.self) { size in
                    Text("\(Int(size)) pt").tag(size)
                }
                if !sizes.contains(document.typography.fontSize) {
                    Text("\(Int(document.typography.fontSize)) pt").tag(document.typography.fontSize)
                }
            }
            Picker("Preset", selection: Binding<TypographyPreset?>(
                get: { TypographyPreset.matching(document.typography) },
                set: { if let preset = $0 { document.setTypography(preset.settings, undoManager: undoManager) } }
            )) {
                Text("Custom").tag(TypographyPreset?.none)
                ForEach(TypographyPreset.allCases) { preset in
                    Text(preset.title).tag(TypographyPreset?.some(preset))
                }
            }
        } header: {
            Text("Document")
        } footer: {
            Text("\(document.totalWordCount.formatted()) words  ·  \(document.orderedSections.count) blocks. Bold, italic and underline on words are kept when the font changes.")
        }
        .onAppear {
            var list = PlatformFont.availableFamilyNames.sorted()
            if !list.contains(document.typography.fontFamily) { list.insert(document.typography.fontFamily, at: 0) }
            families = list
        }
    }
}

private struct BlockInspectorForm: View {
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.undoManager) private var environmentUndoManager
    @Environment(\.documentUndoManager) private var documentUndoManager
    private var undoManager: UndoManager? { documentUndoManager ?? environmentUndoManager }
    @ObservedObject var section: KishoSection

    @State private var synopsisDraft = ""
    @State private var notesDraft = ""
    @FocusState private var focus: Field?
    private enum Field { case synopsis, notes }

    var body: some View {
        Section {
            Picker("Status", selection: Binding(
                get: { section.status },
                set: { document.setStatus($0, for: section, using: undoManager) }
            )) {
                Text("None").tag(BlockStatus?.none)
                ForEach(BlockStatus.allCases) { status in
                    Label(status.title, systemImage: status.symbol).tag(BlockStatus?.some(status))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Colour")
                HStack(spacing: 10) {
                    swatch(nil)
                    ForEach(0..<BlockPalette.count, id: \.self) { index in
                        swatch(index)
                    }
                }
            }
        } header: {
            Text(section.displayTitle)
        } footer: {
            Text(summaryLine)
        }

        Section("Tags") {
            SectionTagsBar(section: section)
                .id(section.id)
        }

        Section {
            TextField("What this block is for", text: $synopsisDraft, axis: .vertical)
                .lineLimit(2...5)
                .focused($focus, equals: .synopsis)
        } header: {
            Text("Synopsis")
        } footer: {
            Text("One or two lines. Shown in the outline when Show Synopses is on.")
        }

        Section {
            TextField("Research, to-dos, things to remember", text: $notesDraft, axis: .vertical)
                .lineLimit(4...12)
                .focused($focus, equals: .notes)
        } header: {
            Text("Notes")
        } footer: {
            Text("Never exported.")
        }

        Section {
            LabeledContent("Created", value: section.createdAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Modified", value: section.modifiedAt.formatted(date: .abbreviated, time: .shortened))
        }
        .font(.footnote)
        .onAppear {
            synopsisDraft = section.synopsis
            notesDraft = section.notes
        }
        .onChange(of: section.synopsis) { new in if focus != .synopsis { synopsisDraft = new } }
        .onChange(of: section.notes) { new in if focus != .notes { notesDraft = new } }
        .onChange(of: focus) { [focus] newFocus in
            // Commit the field being left; one undo step per editing session.
            if focus == .synopsis, newFocus != .synopsis { document.setSynopsis(synopsisDraft, for: section, using: undoManager) }
            if focus == .notes, newFocus != .notes { document.setNotes(notesDraft, for: section, using: undoManager) }
        }
        .onDisappear {
            document.setSynopsis(synopsisDraft, for: section, using: undoManager)
            document.setNotes(notesDraft, for: section, using: undoManager)
        }
    }

    private var summaryLine: String {
        var parts = ["\(section.totalWordCount.formatted()) words"]
        if !section.children.isEmpty { parts.append("\(section.children.count) sub-block\(section.children.count == 1 ? "" : "s")") }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private func swatch(_ index: Int?) -> some View {
        let selected = section.colorIndex == index
        Button {
            document.setColorIndex(index, for: section, using: undoManager)
        } label: {
            ZStack {
                if let index {
                    Circle().fill(BlockPalette.color(index))
                } else {
                    Circle().strokeBorder(Color(uiColor: .separator), lineWidth: 1)
                    Image(systemName: "slash.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                if selected {
                    Circle().strokeBorder(Color.primary.opacity(0.7), lineWidth: 2).padding(-3)
                }
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(index.map { BlockPalette.names[$0] } ?? "No colour")
    }
}
#endif
