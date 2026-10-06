//
//  KishoOutlineView+iOS.swift
//  Kisho
//
//  The block outline on iOS: a sidebar column on iPad, a sheet on iPhone.
//  Rows show the block's colour, title, synopsis (when the preference is
//  on), status and word count, nested by indentation with a chevron to
//  fold sub-blocks. Tapping a row selects the block and scrolls the
//  editor to it without raising the keyboard. A tag filter narrows the
//  rows; a context menu carries the structure commands. Moving blocks is
//  Indent/Outdent across levels and Move Up/Down among siblings (no
//  drag-and-drop yet).
//

#if os(iOS)
import SwiftUI

struct KishoOutlineView: View {
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.undoManager) private var environmentUndoManager
    @Environment(\.documentUndoManager) private var documentUndoManager
    private var undoManager: UndoManager? { documentUndoManager ?? environmentUndoManager }
    @AppStorage(KishoPreferences.Key.showSynopses) private var showSynopses = false
    /// Called after a row is chosen (the iPhone sheet dismisses itself).
    var onChoose: (() -> Void)? = nil

    @State private var collapsed: Set<UUID> = []
    @State private var pendingDelete: KishoSection?

    private struct Row: Identifiable {
        let section: KishoSection
        let depth: Int
        let dimmed: Bool
        var id: UUID { section.id }
    }

    /// Reading-order rows, minus folded subtrees and blocks the tag filter hides.
    private var rows: [Row] {
        var result: [Row] = []
        func walk(_ list: [KishoSection], depth: Int) {
            for section in list {
                let state = filterState(section)
                guard state != .hidden else { continue }
                result.append(Row(section: section, depth: depth, dimmed: state == .context))
                if !collapsed.contains(section.id) { walk(section.children, depth: depth + 1) }
            }
        }
        walk(document.sections, depth: 0)
        return result
    }

    private enum FilterState { case match, context, hidden }

    private func filterState(_ section: KishoSection) -> FilterState {
        guard let tag = document.tagFilter else { return .match }
        if section.tags.contains(tag) { return .match }
        return document.subtreeHasTag(tag, in: section) ? .context : .hidden
    }

    var body: some View {
        VStack(spacing: 0) {
            TagFilterBar()
            ScrollViewReader { proxy in
                // Selection is drawn by hand: List's own selection needs edit
                // mode outside a navigation sidebar.
                List {
                    ForEach(rows) { row in
                        OutlineRow(section: row.section, depth: row.depth, dimmed: row.dimmed,
                                   showSynopsis: showSynopses,
                                   isCollapsed: collapsed.contains(row.section.id),
                                   toggleCollapsed: { toggle(row.section.id) })
                            .id(row.section.id)
                            .onTapGesture { choose(row.section.id) }
                            .listRowInsets(EdgeInsets(top: 6, leading: 12 + CGFloat(min(row.depth, 6)) * 18, bottom: 6, trailing: 12))
                            .listRowBackground(row.section.id == document.selectedSectionID
                                               ? Color.accentColor.opacity(0.14) : Color.clear)
                            .contextMenu { blockMenu(row.section) }
                    }
                }
                .listStyle(.plain)
                .onChange(of: document.selectedSectionID) { id in
                    guard let id else { return }
                    // Unfold the way to the selected block, then show it.
                    reveal(id)
                    withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
                .overlay {
                    if document.sections.isEmpty {
                        ContentUnavailableView("No Blocks", systemImage: "square.stack.3d.up",
                                               description: Text("Add a block to start writing."))
                    }
                }
            }
            Divider()
            OutlineFooter(stats: document.stats)
        }
        .alert("Delete Block?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let section = pendingDelete {
                    document.deleteSection(withID: section.id, using: undoManager)
                    // Like the other outline actions: show the block that
                    // takes the selection, but leave the keyboard down.
                    if let id = document.selectedSectionID { document.requestFocus(id, .body, takesFocus: false) }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("“\(pendingDelete?.displayTitle ?? "")” and its sub-blocks will be deleted.")
        }
    }

    /// Select the block and scroll the editor to it; the keyboard stays down.
    private func choose(_ id: UUID) {
        document.selectedSectionID = id
        document.requestFocus(id, .body, takesFocus: false)
        onChoose?()
    }

    /// Unfolds every ancestor of a block so its row is on screen.
    private func reveal(_ id: UUID) {
        var parent = document.section(withID: id)?.parent
        while let p = parent { collapsed.remove(p.id); parent = p.parent }
    }

    private func toggle(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        }
    }

    /// Structure changes rebuild the cards, which must not happen while the
    /// context menu is still animating away (UIKit crashes tearing down a
    /// text view mid-dismissal), so they run once it has gone.
    private func afterMenu(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: action)
    }

    /// A structure change made from the outline shows its result in the
    /// editor but leaves the keyboard down (the model's own focus request
    /// would raise it); adding a block is the exception, since the next
    /// thing to do is name it.
    private func restructure(_ action: @escaping () -> Void) {
        afterMenu {
            action()
            if let id = document.selectedSectionID {
                // The block may now sit inside a folded parent (Indent into a
                // folded sibling); the selection has not changed, so the
                // onChange above will not unfold it.
                reveal(id)
                document.requestFocus(id, .body, takesFocus: false)
            }
        }
    }

    private func add(_ action: @escaping () -> Void) {
        afterMenu {
            onChoose?()   // the iPhone sheet closes so the title can take the keyboard
            action()
        }
    }

    @ViewBuilder private func blockMenu(_ section: KishoSection) -> some View {
        Button {
            add { document.selectedSectionID = section.id; document.addSiblingSection(using: undoManager) }
        } label: { Label("Add Block After", systemImage: "plus") }
        Button {
            add { document.selectedSectionID = section.id; document.addChildSection(using: undoManager) }
        } label: { Label("Add Sub-block", systemImage: "plus.square.on.square") }
        Divider()
        Button {
            restructure { document.indentSection(withID: section.id, focusing: .body, using: undoManager) }
        } label: { Label("Indent", systemImage: "increase.indent") }
            .disabled(!document.canIndent(sectionID: section.id))
        Button {
            restructure { document.outdentSection(withID: section.id, focusing: .body, using: undoManager) }
        } label: { Label("Outdent", systemImage: "decrease.indent") }
            .disabled(!document.canOutdent(sectionID: section.id))
        Button {
            restructure { document.moveSectionUp(withID: section.id, focusing: .body, using: undoManager) }
        } label: { Label("Move Up", systemImage: "arrow.up") }
            .disabled(!document.canMoveUp(sectionID: section.id))
        Button {
            restructure { document.moveSectionDown(withID: section.id, focusing: .body, using: undoManager) }
        } label: { Label("Move Down", systemImage: "arrow.down") }
            .disabled(!document.canMoveDown(sectionID: section.id))
        Divider()
        Button {
            restructure { document.selectedSectionID = section.id; document.makeChildren(undoManager: undoManager) }
        } label: { Label("Split Paragraphs into Blocks", systemImage: "square.fill.text.grid.1x2") }
            .disabled(!document.canSplit(sectionID: section.id))
        Button {
            restructure { document.selectedSectionID = section.id; document.gather(undoManager: undoManager) }
        } label: { Label("Gather Sub-blocks", systemImage: "rectangle.compress.vertical") }
            .disabled(section.children.isEmpty)
        Divider()
        Button(role: .destructive) {
            pendingDelete = section
        } label: { Label("Delete Block…", systemImage: "trash") }
    }
}

// MARK: - Row

private struct OutlineRow: View {
    @ObservedObject var section: KishoSection
    let depth: Int
    let dimmed: Bool
    let showSynopsis: Bool
    let isCollapsed: Bool
    let toggleCollapsed: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let colour = section.colorIndex {
                Circle().fill(BlockPalette.color(colour)).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(section.displayTitle)
                    .font(depth == 0 ? .body.weight(.semibold) : .body)
                    .lineLimit(1)
                if showSynopsis, !section.synopsis.isEmpty {
                    Text(section.synopsis).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if let status = section.status {
                Image(systemName: status.symbol)
                    .font(.caption)
                    .foregroundStyle(status == .done ? Color.green : Color.secondary)
            }
            let words = section.totalWordCount
            if words > 0 {
                Text("\(words)").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            if !section.children.isEmpty {
                Button(action: toggleCollapsed) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(dimmed ? 0.45 : 1)
        .contentShape(Rectangle())
    }
}

// MARK: - Tag filter and footer

private struct TagFilterBar: View {
    @EnvironmentObject var document: KishoDocumentModel

    var body: some View {
        let tags = document.allTags
        if !tags.isEmpty || document.tagFilter != nil {
            HStack(spacing: 8) {
                Menu {
                    Picker("Tag filter", selection: $document.tagFilter) {
                        Text("All blocks").tag(String?.none)
                        ForEach(tags, id: \.self) { tag in
                            Text(tag).tag(String?.some(tag))
                        }
                    }
                } label: {
                    Label(document.tagFilter ?? "All blocks", systemImage: "tag")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                Spacer()
                if document.tagFilter != nil {
                    Button { document.tagFilter = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear filter")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onChange(of: tags) { newTags in
                if let f = document.tagFilter, !newTags.contains(f) { document.tagFilter = nil }
            }
            Divider()
        }
    }
}

/// Word/block totals; observes the lightweight stats signal.
private struct OutlineFooter: View {
    @EnvironmentObject var document: KishoDocumentModel
    @ObservedObject var stats: KishoDocumentModel.Stats

    var body: some View {
        HStack {
            Text("\(document.totalWordCount.formatted()) words")
            Spacer()
            Text("\(document.orderedSections.count) blocks")
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
#endif
