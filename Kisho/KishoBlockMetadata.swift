//
//  KishoBlockMetadata.swift
//  Kisho
//
//  Planning metadata on a block beyond tags — status, colour, synopsis,
//  notes — and the inspector panel that edits it. The sidebar shows the
//  colour and status so it works as a planning surface; the text itself is
//  untouched by any of this.
//

import SwiftUI

// MARK: - Model types

enum BlockStatus: String, Codable, CaseIterable, Identifiable {
    case draft, revised, final, done
    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: return "Draft"
        case .revised: return "Revised"
        case .final: return "Final"
        case .done: return "Done"
        }
    }

    /// SF Symbol shown in the sidebar and inspector.
    var symbol: String {
        switch self {
        case .draft: return "pencil"
        case .revised: return "arrow.triangle.2.circlepath"
        case .final: return "checkmark.seal"
        case .done: return "checkmark.circle.fill"
        }
    }
}

/// Eight fixed swatches, so the sidebar stays calm and colours mean the
/// same thing across documents. Stored as the index.
enum BlockPalette {
    static let names = ["Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Grey"]

    static var count: Int { names.count }

    static func color(_ index: Int) -> Color {
        #if os(macOS)
        let ns: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen,
                             .systemTeal, .systemBlue, .systemPurple, .systemGray]
        return Color(nsColor: ns[max(0, min(index, ns.count - 1))])
        #else
        let ui: [Color] = [.red, .orange, .yellow, .green, .teal, .blue, .purple, .gray]
        return ui[max(0, min(index, ui.count - 1))]
        #endif
    }

    static func isValid(_ index: Int?) -> Bool {
        guard let index else { return true }
        return (0..<count).contains(index)
    }
}

#if os(macOS)

// MARK: - Inspector

/// The right-hand panel: the document's typography at the top, then the
/// metadata of the selected block.
struct BlockInspectorView: View {
    @EnvironmentObject var document: KishoDocumentModel

    var body: some View {
        VStack(spacing: 0) {
            DocumentInspectorSection()
            Divider()
            if let section = document.selectedSection {
                BlockInspectorForm(section: section)
                    .id(section.id)   // fresh drafts per block
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No block selected")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 270)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Document-wide settings: the font family and size every block uses
/// (per-word bold/italic/underline are kept when these change) and the
/// named presets from the Format menu.
private struct DocumentInspectorSection: View {
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.undoManager) private var undoManager
    @State private var families: [String] = []

    private let sizes: [Double] = [10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 22, 24, 28]

    var body: some View {
        let typography = Binding<TypographySettings>(
            get: { document.typography },
            set: { document.setTypography($0, undoManager: undoManager) }
        )
        VStack(alignment: .leading, spacing: 8) {
            Text("DOCUMENT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.6)

            Picker("Font", selection: typography.fontFamily) {
                ForEach(families, id: \.self) { family in
                    Text(TypographySettings.displayName(forFamily: family)).tag(family)
                }
            }
            .labelsHidden()
            .help("Font family for the whole document")

            HStack(spacing: 8) {
                Picker("Size", selection: typography.fontSize) {
                    ForEach(sizes, id: \.self) { size in
                        Text("\(Int(size)) pt").tag(size)
                    }
                    if !sizes.contains(document.typography.fontSize) {
                        Text("\(Int(document.typography.fontSize)) pt").tag(document.typography.fontSize)
                    }
                }
                .labelsHidden()
                .frame(width: 84)
                .help("Font size for the whole document")

                Picker("Preset", selection: Binding<TypographyPreset?>(
                    get: { TypographyPreset.matching(document.typography) },
                    set: { if let preset = $0 { document.setTypography(preset.settings, undoManager: undoManager) } }
                )) {
                    Text("Preset…").tag(TypographyPreset?.none)
                    ForEach(TypographyPreset.allCases) { preset in
                        Text(preset.title).tag(TypographyPreset?.some(preset))
                    }
                }
                .labelsHidden()
                .help("Named font and size combinations (also in Format ▸ Document Font)")
            }
            Text("\(document.totalWordCount.formatted()) words  ·  \(document.orderedSections.count) blocks")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .onAppear {
            var list = NSFontManager.shared.availableFontFamilies.sorted()
            if !list.contains(document.typography.fontFamily) { list.insert(document.typography.fontFamily, at: 0) }
            families = list
        }
    }
}

private struct BlockInspectorForm: View {
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.undoManager) private var undoManager
    @ObservedObject var section: KishoSection

    @State private var synopsisDraft = ""
    @State private var notesDraft = ""
    @FocusState private var focus: Field?
    private enum Field { case synopsis, notes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Heading
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Status
                VStack(alignment: .leading, spacing: 6) {
                    label("Status")
                    Picker("Status", selection: Binding(
                        get: { section.status },
                        set: { document.setStatus($0, for: section, using: undoManager) }
                    )) {
                        Text("None").tag(BlockStatus?.none)
                        ForEach(BlockStatus.allCases) { status in
                            Label(status.title, systemImage: status.symbol).tag(BlockStatus?.some(status))
                        }
                    }
                    .labelsHidden()
                }

                // Colour
                VStack(alignment: .leading, spacing: 6) {
                    label("Colour")
                    HStack(spacing: 8) {
                        swatch(nil)
                        ForEach(0..<BlockPalette.count, id: \.self) { index in
                            swatch(index)
                        }
                    }
                }

                // Synopsis
                VStack(alignment: .leading, spacing: 6) {
                    label("Synopsis")
                    TextEditor(text: $synopsisDraft)
                        .font(.body)
                        .frame(minHeight: 64, maxHeight: 110)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                        .focused($focus, equals: .synopsis)
                    Text("One or two lines: what this block is for. Shown in the sidebar when View ▸ Show Synopses is on.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Notes
                VStack(alignment: .leading, spacing: 6) {
                    label("Notes")
                    TextEditor(text: $notesDraft)
                        .font(.body)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                        .focused($focus, equals: .notes)
                    Text("Research, to-dos, things to remember. Never exported.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Dates
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created \(section.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    Text("Modified \(section.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
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
        if !section.tags.isEmpty { parts.append(section.tags.joined(separator: ", ")) }
        return parts.joined(separator: "  ·  ")
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .kerning(0.6)
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
                    Circle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    Image(systemName: "slash.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                if selected {
                    Circle().strokeBorder(Color.primary.opacity(0.7), lineWidth: 2).padding(-3)
                }
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(index.map { BlockPalette.names[$0] } ?? "No colour")
    }
}

// MARK: - Commands

/// View ▸ Show Inspector / Show Synopses in Sidebar. Both are app-wide
/// preferences, so they live in UserDefaults rather than the document.
struct InspectorCommands: Commands {
    @AppStorage(KishoPreferences.Key.showInspector) private var showInspector = true
    @AppStorage(KishoPreferences.Key.showSynopses) private var showSynopses = false

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(showInspector ? "Hide Inspector" : "Show Inspector") { showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Toggle("Show Synopses in Sidebar", isOn: $showSynopses)
            Divider()
        }
    }
}
#endif
