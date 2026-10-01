//
//  KishoDocumentModel.swift
//  Kisho
//
//  Created by Peter Macdonald on 03/06/2025.
//

import SwiftUI
import RichTextEditor

final class KishoDocumentModel: ObservableObject, Codable {
    /// Top-level sections. Their `parent` is always nil.
    @Published var sections: [KishoSection] {
        didSet { sections.forEach { $0.parent = nil } }
    }
    @Published var selectedSectionID : UUID? = nil
    @Published var typography: TypographySettings = TypographySettings()

    /// Asks the editor to scroll to a block and put the keyboard focus in its
    /// title or body. Set by the sidebar, navigation and structural edits;
    /// *not* set when the selection changes because the user clicked into a
    /// block in the editor (their caret is already where they want it).
    @Published var focusRequest: EditorFocusRequest?

    /// Lightweight change signal for views that show document-wide figures
    /// (word count footer). Bumped on body edits so those views refresh
    /// without the whole document re-rendering on every keystroke.
    final class Stats: ObservableObject {
        @Published var version = 0
    }
    let stats = Stats()

    func requestFocus(_ sectionID: UUID?, _ field: EditorFocusRequest.Field,
                      caret: Int? = nil, selection: NSRange? = nil, takesFocus: Bool = true) {
        guard let sectionID else { return }
        focusRequest = EditorFocusRequest(sectionID: sectionID, field: field, caret: caret,
                                          selection: selection, takesFocus: takesFocus)
    }

    /// Sidebar tag filter (UI state; not saved with the document). Rows whose
    /// block carries the tag are shown; their ancestors are shown dimmed;
    /// everything else is hidden.
    @Published var tagFilter: String?

    /// Flush live editor text into the section tree before a structural edit.
    var beforeStructureEdit: (() -> Void)?
    /// Rebuild the editor after a structural edit and ignore stale text-view writebacks.
    var afterStructureEdit: (() -> Void)?

    private var structureEditDepth = 0

    enum CodingKeys: String, CodingKey { case formatVersion, sections, typography, selectedSectionID }

    /// Version of the on-disk JSON. Files without the key are version 0 (the
    /// pre-1.0 layout, which reads identically). Bump when a change needs
    /// migration; a newer file than this build understands is refused rather
    /// than half-read and then saved back with its extra data lost.
    static let currentFormatVersion = 2   // 2: block status/colour/synopsis/notes

    enum FormatError: LocalizedError {
        case newerThanThisVersion(Int)
        // AppKit's "could not be opened" alert shows the failure reason and
        // recovery suggestion under its own title line; the description is
        // what callers see when they present the error themselves.
        var errorDescription: String? { "This document was saved by a newer version of Kisho." }
        var failureReason: String? {
            switch self {
            case .newerThanThisVersion(let version):
                return "It uses document format \(version); this version of Kisho reads up to \(KishoDocumentModel.currentFormatVersion)."
            }
        }
        var recoverySuggestion: String? { "Update Kisho to open it." }
    }

    /// Which field a newly added block puts the keyboard in. Read from the
    /// preferences each time so a change in Settings applies at once;
    /// tests replace the closure.
    var newBlockFocus: () -> EditorFocusRequest.Field = { KishoPreferences.newBlockFocus }

    var selectedSection : KishoSection? {
        guard let id = self.selectedSectionID else { return nil }
        return self.section(withID: id, inSections: self.sections)
    }

    init(sections: [KishoSection] = [KishoSection(title: KishoSection.defaultTitle)]) {
        self.sections = sections
        self.selectedSectionID = sections.first?.id
        sections.forEach { $0.parent = nil }
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 0
        guard version <= Self.currentFormatVersion else {
            throw FormatError.newerThanThisVersion(version)
        }
        let decoded = try container.decode([KishoSection].self, forKey: .sections)
        typography = try container.decodeIfPresent(TypographySettings.self, forKey: .typography) ?? TypographySettings()
        sections = decoded
        decoded.forEach { $0.parent = nil }

        // A document saved with nothing selected stores `null`; that must not
        // stop the file from opening. Fall back to the first section, and
        // ignore a selection that no longer exists.
        let selected = try container.decodeIfPresent(UUID.self, forKey: .selectedSectionID)
        if let selected, section(withID: selected, inSections: decoded) != nil {
            selectedSectionID = selected
        } else {
            selectedSectionID = decoded.first?.id
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentFormatVersion, forKey: .formatVersion)
        try container.encode(sections, forKey: .sections)
        try container.encode(selectedSectionID, forKey: .selectedSectionID)
        try container.encode(typography, forKey: .typography)
    }

    // MARK: - Lookup

    func section(withID id: UUID, inSections: [KishoSection]) -> KishoSection? {
        for s in inSections {
            if s.id == id { return s }
            if let found = section(withID: id, inSections: s.children) {
                return found
            }
        }
        return nil
    }

    func section(withID id: UUID) -> KishoSection? {
        section(withID: id, inSections: sections)
    }

    /// Parent of the section with the given ID, or nil for a top-level section
    /// (and for an unknown ID). Found by search, so it never relies on cached
    /// pointers.
    func parent(forSectionID id: UUID, inSections: [KishoSection]) -> KishoSection? {
        for s in inSections {
            if s.children.contains(where: { $0.id == id }) {
                return s
            }
            if let sub = parent(forSectionID: id, inSections: s.children) {
                return sub
            }
        }
        return nil
    }

    /// Where a section currently lives: its parent (nil at top level) and its
    /// index in that parent's list.
    func location(ofSectionID id: UUID) -> (parent: KishoSection?, index: Int)? {
        if let parent = parent(forSectionID: id, inSections: sections),
           let idx = parent.children.firstIndex(where: { $0.id == id }) {
            return (parent, idx)
        }
        if let idx = sections.firstIndex(where: { $0.id == id }) {
            return (nil, idx)
        }
        return nil
    }

    /// Every section in reading (pre-order) order: a section, then its
    /// descendants, then its next sibling.
    var orderedSections: [KishoSection] {
        KishoSection.allSections(in: sections)
    }

    public func depth(forSection: KishoSection) -> Int {
        var depth = 0
        var parent = self.parent(forSectionID: forSection.id, inSections: self.sections)
        while let pa = parent {
            depth += 1
            parent = self.parent(forSectionID: pa.id, inSections: self.sections)
        }
        return depth
    }

    /// Words in the whole document.
    var totalWordCount: Int {
        sections.reduce(0) { $0 + $1.totalWordCount }
    }

    var allTags: [String] {
        Set(orderedSections.flatMap { $0.tags }).sorted()
    }

    // MARK: - Selection & navigation

    func select(section: KishoSection) {
        selectedSectionID = section.id
        requestFocus(section.id, .body)
    }

    /// Next section in reading order (into children first).
    func selectNext() {
        let all = orderedSections
        guard !all.isEmpty else { return }
        guard let current = selectedSectionID,
              let idx = all.firstIndex(where: { $0.id == current }) else {
            selectedSectionID = all.first?.id
            return
        }
        selectedSectionID = all[min(idx + 1, all.count - 1)].id
        requestFocus(selectedSectionID, .body)
    }

    /// Previous section in reading order.
    func selectPrevious() {
        let all = orderedSections
        guard !all.isEmpty else { return }
        guard let current = selectedSectionID,
              let idx = all.firstIndex(where: { $0.id == current }) else {
            selectedSectionID = all.first?.id
            return
        }
        selectedSectionID = all[max(idx - 1, 0)].id
        requestFocus(selectedSectionID, .body)
    }

    /// First child of the selected section, or the next section if it has none.
    func selectDown() {
        if let selected = selectedSection, let first = selected.children.first {
            selectedSectionID = first.id
            requestFocus(first.id, .body)
        } else {
            selectNext()
        }
    }

    /// Parent of the selected section, or the previous section at top level.
    func selectUp() {
        if let selected = selectedSection,
           let parent = parent(forSectionID: selected.id, inSections: sections) {
            selectedSectionID = parent.id
            requestFocus(parent.id, .body)
        } else {
            selectPrevious()
        }
    }

    // MARK: - Structural edits (all undoable, all symmetric undo/redo)

    /// Runs a structural change with the editor flush/rebuild hooks around it.
    /// Nested calls (e.g. a move = remove + insert, or an undo that calls back
    /// into these helpers) only fire the hooks once, at the outermost level.
    private func withStructureEdit(_ body: () -> Void) {
        if structureEditDepth == 0 { beforeStructureEdit?() }
        structureEditDepth += 1
        body()
        structureEditDepth -= 1
        if structureEditDepth == 0 { afterStructureEdit?() }
    }

    /// Performs `forward` now and registers `inverse` as its undo. Undoing
    /// registers `forward` again as the redo, so every operation is fully
    /// reversible in both directions.
    private func perform(
        _ name: String,
        using undoManager: UndoManager?,
        forward: @escaping (KishoDocumentModel) -> Void,
        inverse: @escaping (KishoDocumentModel) -> Void
    ) {
        withStructureEdit { forward(self) }
        registerReversible(undoManager, name: name, undo: inverse, redo: forward)
    }

    private func registerReversible(
        _ undoManager: UndoManager?,
        name: String,
        undo: @escaping (KishoDocumentModel) -> Void,
        redo: @escaping (KishoDocumentModel) -> Void
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { [weak undoManager] target in
            target.withStructureEdit { undo(target) }
            target.registerReversible(undoManager, name: name, undo: redo, redo: undo)
        }
        undoManager.setActionName(name)
    }

    // Raw tree mutations: no undo, no hooks. Parent pointers are kept in sync
    // by the `children` / `sections` property observers.

    private func rawInsert(_ section: KishoSection, into parent: KishoSection?, at index: Int) {
        if let parent {
            let idx = max(0, min(index, parent.children.count))
            parent.children.insert(section, at: idx)
        } else {
            let idx = max(0, min(index, sections.count))
            sections.insert(section, at: idx)
        }
    }

    @discardableResult
    private func rawRemove(_ section: KishoSection) -> (parent: KishoSection?, index: Int)? {
        guard let loc = location(ofSectionID: section.id) else { return nil }
        if let parent = loc.parent {
            parent.children.remove(at: loc.index)
        } else {
            sections.remove(at: loc.index)
        }
        section.parent = nil
        return loc
    }

    /// The section to select once `section` (at `parent`/`index`) is gone:
    /// the previous sibling, else the sibling that takes its place, else the
    /// parent, else the first section in the document.
    private func selectionAfterRemoving(parent: KishoSection?, index: Int) -> UUID? {
        let siblings = parent?.children ?? sections
        if index > 0, index - 1 < siblings.count { return siblings[index - 1].id }
        if index < siblings.count { return siblings[index].id }
        return parent?.id ?? sections.first?.id
    }

    // MARK: Add

    /// Inserts a new section immediately after the selected one, at the same
    /// level. With nothing selected it goes at the end of the top level.
    func addSiblingSection(using undoManager: UndoManager? = nil) {
        let parent: KishoSection?
        let index: Int
        if let selectedID = selectedSectionID, let loc = location(ofSectionID: selectedID) {
            parent = loc.parent
            index = loc.index + 1
        } else {
            parent = nil
            index = sections.count
        }
        insertNewSection(into: parent, at: index, name: "Add Block", using: undoManager)
    }

    /// Appends a new section as the last child of the selected one. With
    /// nothing selected it goes at the end of the top level.
    func addChildSection(using undoManager: UndoManager? = nil) {
        if let selected = selectedSection {
            insertNewSection(into: selected, at: selected.children.count, name: "Add Child Block", using: undoManager)
        } else {
            insertNewSection(into: nil, at: sections.count, name: "Add Block", using: undoManager)
        }
    }

    private func insertNewSection(into parent: KishoSection?, at index: Int, name: String, using undoManager: UndoManager?) {
        let newSection = KishoSection(title: KishoSection.defaultTitle)
        let previousSelection = selectedSectionID
        perform(name, using: undoManager, forward: { target in
            target.rawInsert(newSection, into: parent, at: index)
            target.selectedSectionID = newSection.id
            target.requestFocus(newSection.id, target.newBlockFocus())
        }, inverse: { target in
            target.rawRemove(newSection)
            target.selectedSectionID = previousSelection.flatMap { target.section(withID: $0) }?.id
                ?? target.selectionAfterRemoving(parent: parent, index: index)
            target.requestFocus(target.selectedSectionID, .body)
        })
    }

    // MARK: Delete

    func deleteSelectedSection(using undoManager: UndoManager? = nil) {
        guard let id = selectedSectionID else { return }
        deleteSection(withID: id, using: undoManager)
    }

    func deleteSection(withID id: UUID, using undoManager: UndoManager? = nil) {
        guard let section = section(withID: id), let loc = location(ofSectionID: id) else { return }
        let parent = loc.parent
        let index = loc.index
        let previousSelection = selectedSectionID
        perform("Delete Block", using: undoManager, forward: { target in
            target.rawRemove(section)
            if target.selectedSectionID == id || target.selectedSectionID.map({ section.contains(sectionID: $0) }) == true {
                target.selectedSectionID = target.selectionAfterRemoving(parent: parent, index: index)
                target.requestFocus(target.selectedSectionID, .body)
            }
        }, inverse: { target in
            target.rawInsert(section, into: parent, at: index)
            target.selectedSectionID = previousSelection ?? section.id
            target.requestFocus(target.selectedSectionID, .body)
        })
    }

    // MARK: Move

    enum MoveDestination {
        case before(UUID)
        case after(UUID)
        case into(UUID)

        var targetID: UUID {
            switch self {
            case .before(let id), .after(let id), .into(let id): return id
            }
        }
    }

    /// Whether a section may be moved to the destination: never onto itself
    /// or into its own subtree.
    func canMove(sectionID draggedID: UUID, to destination: MoveDestination) -> Bool {
        guard draggedID != destination.targetID,
              let dragged = section(withID: draggedID),
              section(withID: destination.targetID) != nil else { return false }
        return !dragged.contains(sectionID: destination.targetID)
    }

    /// Moves a section before/after another section or into it as its last
    /// child. Invalid moves (onto itself, into its own subtree, unknown IDs)
    /// are ignored and the tree is left untouched.
    func move(sectionID draggedID: UUID, to destination: MoveDestination,
              focusing field: EditorFocusRequest.Field = .body, using undoManager: UndoManager? = nil) {
        guard canMove(sectionID: draggedID, to: destination),
              let dragged = section(withID: draggedID),
              let origin = location(ofSectionID: draggedID) else { return }

        // Work out the target slot with the dragged section already removed,
        // so indices are right even when moving within the same parent.
        rawRemove(dragged)
        var targetParent: KishoSection? = nil
        var targetIndex: Int? = nil
        switch destination {
        case .before(let id):
            if let loc = location(ofSectionID: id) {
                targetParent = loc.parent
                targetIndex = loc.index
            }
        case .after(let id):
            if let loc = location(ofSectionID: id) {
                targetParent = loc.parent
                targetIndex = loc.index + 1
            }
        case .into(let id):
            if let newParent = section(withID: id) {
                targetParent = newParent
                targetIndex = newParent.children.count
            }
        }
        // Put it back before doing the real, undoable move.
        rawInsert(dragged, into: origin.parent, at: origin.index)
        guard let targetIndex else { return }
        let target = (parent: targetParent, index: targetIndex)

        // No-op if it would land exactly where it already is.
        if target.parent === origin.parent, target.index == origin.index { return }

        let previousSelection = selectedSectionID
        perform("Move Block", using: undoManager, forward: { t in
            t.rawRemove(dragged)
            t.rawInsert(dragged, into: target.parent, at: target.index)
            t.selectedSectionID = dragged.id
            t.requestFocus(dragged.id, field)
        }, inverse: { t in
            t.rawRemove(dragged)
            t.rawInsert(dragged, into: origin.parent, at: origin.index)
            t.selectedSectionID = previousSelection
            t.requestFocus(previousSelection, field)
        })
    }

    // MARK: Indent / outdent (outliner Tab / ⇧Tab)

    /// Whether the block can become the last child of the sibling above it.
    func canIndent(sectionID id: UUID) -> Bool {
        guard let loc = location(ofSectionID: id), loc.index > 0 else { return false }
        return true
    }

    /// Whether the block can move out to sit after its parent.
    func canOutdent(sectionID id: UUID) -> Bool {
        location(ofSectionID: id)?.parent != nil
    }

    /// Makes the block the last child of the sibling above it (its own
    /// children come along). The first child of a parent has nowhere to go.
    func indentSection(withID id: UUID, focusing field: EditorFocusRequest.Field = .body,
                       using undoManager: UndoManager? = nil) {
        guard let loc = location(ofSectionID: id), loc.index > 0 else { return }
        let siblings = loc.parent?.children ?? sections
        move(sectionID: id, to: .into(siblings[loc.index - 1].id), focusing: field, using: undoManager)
    }

    /// Moves the block out of its parent to sit directly after it. Siblings
    /// that followed it stay with the parent. Top-level blocks can't outdent.
    func outdentSection(withID id: UUID, focusing field: EditorFocusRequest.Field = .body,
                        using undoManager: UndoManager? = nil) {
        guard let parent = location(ofSectionID: id)?.parent else { return }
        move(sectionID: id, to: .after(parent.id), focusing: field, using: undoManager)
    }

    func indentSelectedSection(using undoManager: UndoManager? = nil) {
        guard let id = selectedSectionID else { return }
        indentSection(withID: id, using: undoManager)
    }

    func outdentSelectedSection(using undoManager: UndoManager? = nil) {
        guard let id = selectedSectionID else { return }
        outdentSection(withID: id, using: undoManager)
    }

    // Compatibility wrappers for existing call sites.
    func moveAsSibling(draggedID: UUID, destinationID: UUID, insertBefore: Bool, using undoManager: UndoManager? = nil) {
        move(sectionID: draggedID, to: insertBefore ? .before(destinationID) : .after(destinationID), using: undoManager)
    }

    func moveAsChild(draggedID: UUID, destinationID: UUID, using undoManager: UndoManager? = nil) {
        move(sectionID: draggedID, to: .into(destinationID), using: undoManager)
    }

    // MARK: Split / Gather

    /// Turns each paragraph of the selected section's body into a new child
    /// section (inserted before any existing children, since the paragraphs
    /// precede them in reading order) and empties the body.
    func makeChildren(undoManager: UndoManager? = nil) {
        // withStructureEdit flushes live typing first so the split sees it;
        // the nested perform() then fires no further hooks.
        withStructureEdit {
            guard let section = selectedSection else { return }
            let newSections = section.asSections()
            guard !newSections.isEmpty else { return }

            let originalTitle = section.title
            let originalContent = NSAttributedString(attributedString: section.content.attributedString)
            let originalChildren = section.children
            let previousSelection = selectedSectionID

            let newTitle = section.titleFirstLine
            let newChildren = newSections + originalChildren

            perform("Split Paragraphs", using: undoManager, forward: { target in
                section.title = newTitle
                section.content.attributedString = NSAttributedString(string: "")
                section.children = newChildren
                section.modifiedAt = Date()
                target.selectedSectionID = newSections.first?.id
                target.requestFocus(newSections.first?.id, .body)
            }, inverse: { target in
                section.title = originalTitle
                section.content.attributedString = originalContent
                section.children = originalChildren
                section.modifiedAt = Date()
                target.selectedSectionID = previousSelection
                target.requestFocus(previousSelection, .body)
            })
        }
    }

    /// Merges the bodies of all descendants (in reading order) into the
    /// selected section's body and removes them.
    func gather(undoManager: UndoManager? = nil) {
        withStructureEdit {
            guard let section = selectedSection, !section.children.isEmpty else { return }

            let originalContent = NSAttributedString(attributedString: section.content.attributedString)
            let originalChildren = section.children
            let gathered = section.joinedChildrenContent().attributedString
            let previousSelection = selectedSectionID

            perform("Gather Blocks", using: undoManager, forward: { target in
                section.content.attributedString = gathered
                section.children = []
                section.modifiedAt = Date()
                target.selectedSectionID = section.id
                target.requestFocus(section.id, .body)
            }, inverse: { target in
                section.content.attributedString = originalContent
                section.children = originalChildren
                section.modifiedAt = Date()
                target.selectedSectionID = previousSelection
                target.requestFocus(previousSelection, .body)
            })
        }
    }

    // MARK: Title / body edits (card editor)

    /// Renames a section, undoably. Whitespace-only titles are cleared so the
    /// display falls back to a title derived from the content.
    func setTitle(_ title: String, for section: KishoSection, using undoManager: UndoManager? = nil) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned != section.title else { return }
        let old = section.title
        section.title = cleaned
        section.modifiedAt = Date()
        registerReversible(undoManager, name: "Rename Block",
                           undo: { t in section.title = old; t.selectedSectionID = section.id; t.requestFocus(section.id, .title) },
                           redo: { t in section.title = cleaned; t.selectedSectionID = section.id; t.requestFocus(section.id, .title) })
    }

    private struct BodyEditBurst {
        var start: NSAttributedString
        var startCaret: Int
        var lastEdit: Date
        var lastLocation: Int
        var lastLength: Int
    }
    private var bodyEditBursts: [UUID: BodyEditBurst] = [:]
    private static let bodyEditBurstInterval: TimeInterval = 1.0

    /// Registers undo for a body edit the editor has already applied to the
    /// model. Consecutive keystrokes coalesce into one undo step; a burst ends
    /// on a pause of a second, a paragraph break, or a caret jump (an edit
    /// that is not adjacent to the previous one), so ⌘Z takes back a run of
    /// typing rather than one character — or a whole session.
    ///
    /// - Parameter editLocation: character index where the edit happened.
    func recordBodyEdit(for section: KishoSection,
                        from old: NSAttributedString,
                        to new: NSAttributedString,
                        editLocation: Int = 0,
                        using undoManager: UndoManager? = nil) {
        assert(old !== new, "recordBodyEdit needs a pre-edit snapshot, not the live text storage")
        section.modifiedAt = Date()
        publishAncestorChange(of: section)
        guard let undoManager else { return }

        let now = Date()
        let insertedParagraphBreak = paragraphBreaks(in: new.string) > paragraphBreaks(in: old.string)

        if var burst = bodyEditBursts[section.id],
           now.timeIntervalSince(burst.lastEdit) < Self.bodyEditBurstInterval,
           abs(editLocation - burst.lastLocation) <= max(1, abs(new.length - burst.lastLength) + 1) {
            burst.lastEdit = insertedParagraphBreak ? .distantPast : now
            burst.lastLocation = editLocation
            burst.lastLength = new.length
            bodyEditBursts[section.id] = burst
            return
        }

        let start = NSAttributedString(attributedString: old)
        bodyEditBursts[section.id] = BodyEditBurst(
            start: start,
            startCaret: editLocation,
            lastEdit: insertedParagraphBreak ? .distantPast : now,
            lastLocation: editLocation,
            lastLength: new.length
        )
        registerBodyRestore(undoManager, section: section, restore: start, caret: editLocation)
    }

    private func paragraphBreaks(in string: String) -> Int {
        string.reduce(0) { $0 + ($1 == "\n" || $1 == "\r" || $1 == "\u{2029}" ? 1 : 0) }
    }

    /// Ancestors show subtree word counts, and the footer shows the document
    /// total; neither observes the edited block, so tell them.
    private func publishAncestorChange(of section: KishoSection) {
        var parent = section.parent
        while let p = parent {
            p.objectWillChange.send()
            parent = p.parent
        }
        stats.version &+= 1
    }

    private func registerBodyRestore(_ undoManager: UndoManager, section: KishoSection,
                                     restore: NSAttributedString, caret: Int) {
        // In the app the undo manager groups by event, so each new burst is its
        // own step automatically. When grouping is manual (tests), give each
        // burst its own group so steps stay separate.
        let needsGroup = !undoManager.groupsByEvent && undoManager.groupingLevel == 0
        if needsGroup { undoManager.beginUndoGrouping() }
        defer { if needsGroup { undoManager.endUndoGrouping() } }

        undoManager.registerUndo(withTarget: self) { [weak undoManager] target in
            let current = NSAttributedString(attributedString: section.content.attributedString)
            // Redo should put the caret after the text it brings back.
            let redoCaret = min(caret + max(0, current.length - restore.length), current.length)
            section.content.attributedString = restore
            section.modifiedAt = Date()
            target.publishAncestorChange(of: section)
            target.bodyEditBursts[section.id] = nil
            // Bring the caret to the edit site in the block whose text changed.
            target.selectedSectionID = section.id
            target.requestFocus(section.id, .body, caret: min(caret, restore.length))
            if let undoManager {
                target.registerBodyRestore(undoManager, section: section, restore: current, caret: redoCaret)
            }
        }
        undoManager.setActionName("Typing")
    }

    // MARK: Tags

    /// Replaces a section's tags, registering the change with the undo
    /// manager (which is also what marks the document as needing a save).
    func setTags(_ tags: [String], for section: KishoSection, using undoManager: UndoManager? = nil) {
        let cleaned = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard cleaned != section.tags else { return }
        let old = section.tags
        objectWillChange.send()
        section.tags = cleaned
        registerReversible(undoManager, name: "Edit Tags",
                           undo: { target in target.objectWillChange.send(); section.tags = old },
                           redo: { target in target.objectWillChange.send(); section.tags = cleaned })
    }

    // MARK: Block metadata (status, colour, synopsis, notes)

    func setStatus(_ status: BlockStatus?, for section: KishoSection, using undoManager: UndoManager? = nil) {
        guard status != section.status else { return }
        let old = section.status
        objectWillChange.send()
        section.status = status
        registerReversible(undoManager, name: "Change Status",
                           undo: { t in t.objectWillChange.send(); section.status = old },
                           redo: { t in t.objectWillChange.send(); section.status = status })
    }

    func setColorIndex(_ index: Int?, for section: KishoSection, using undoManager: UndoManager? = nil) {
        let index = BlockPalette.isValid(index) ? index : nil
        guard index != section.colorIndex else { return }
        let old = section.colorIndex
        objectWillChange.send()
        section.colorIndex = index
        registerReversible(undoManager, name: "Change Colour",
                           undo: { t in t.objectWillChange.send(); section.colorIndex = old },
                           redo: { t in t.objectWillChange.send(); section.colorIndex = index })
    }

    func setSynopsis(_ synopsis: String, for section: KishoSection, using undoManager: UndoManager? = nil) {
        let cleaned = synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned != section.synopsis else { return }
        let old = section.synopsis
        objectWillChange.send()
        section.synopsis = cleaned
        registerReversible(undoManager, name: "Edit Synopsis",
                           undo: { t in t.objectWillChange.send(); section.synopsis = old },
                           redo: { t in t.objectWillChange.send(); section.synopsis = cleaned })
    }

    func setNotes(_ notes: String, for section: KishoSection, using undoManager: UndoManager? = nil) {
        let cleaned = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned != section.notes else { return }
        let old = section.notes
        objectWillChange.send()
        section.notes = cleaned
        registerReversible(undoManager, name: "Edit Notes",
                           undo: { t in t.objectWillChange.send(); section.notes = old },
                           redo: { t in t.objectWillChange.send(); section.notes = cleaned })
    }

    // MARK: Typography

    /// Changes the document typography and applies it to every section, as one
    /// undoable step that also restores the previous settings.
    func setTypography(_ settings: TypographySettings, undoManager: UndoManager? = nil) {
        guard settings != typography else { return }
        let previous = typography
        typography = settings
        applyTypographyToEntireDocument(previousSettings: previous, undoManager: undoManager)
    }

    /// Applies the current typography settings to every section, undoably.
    func applyTypographyToEntireDocument(previousSettings: TypographySettings? = nil, undoManager: UndoManager? = nil) {
        let settings = self.typography
        let previousSettings = previousSettings ?? settings

        // Family and size only; bold/italic are per-selection and preserved.
        let font = settings.baseFont

        // Use the appearance-adaptive label color so text follows light/dark mode
        // instead of baking a static black into the rich text.
        let nsColor = PlatformColor.label

        // Flush live typing first so the snapshot (and the fonts) include it.
        withStructureEdit {
            let before = KishoSection.documentSnapshot(of: sections)

            for section in sections {
                section.applyTypographyToSelfAndDescendants(font: font, color: nsColor)
            }

            let after = KishoSection.documentSnapshot(of: sections)
            registerReversible(undoManager, name: "Change Typography", undo: { target in
                target.typography = previousSettings
                KishoSection.applyDocumentSnapshot(before, to: target.sections)
            }, redo: { target in
                target.typography = settings
                KishoSection.applyDocumentSnapshot(after, to: target.sections)
            })
        }
    }
}

/// See `KishoDocumentModel.focusRequest`. Each request is unique (token) so
/// repeating the same target still triggers the editor.
struct EditorFocusRequest: Equatable {
    enum Field { case title, body }
    let sectionID: UUID
    let field: Field
    /// Caret position within the body (nil = end of text).
    var caret: Int? = nil
    /// Text range to select within the body (takes precedence over `caret`).
    var selection: NSRange? = nil
    /// False to scroll to and mark the place without moving keyboard focus
    /// there (the find bar stepping through matches keeps its own focus).
    var takesFocus: Bool = true
    let token = UUID()
}

extension FocusedValues {
    // 1) A key for passing the document model down the responder chain
    private struct DocumentModelKey: FocusedValueKey {
        typealias Value = KishoDocumentModel
    }
    var kishoDocumentModel: KishoDocumentModel? {
        get { self[DocumentModelKey.self] }
        set { self[DocumentModelKey.self] = newValue }
    }

    // 2) A key for passing the selected‐section ID (a Binding<UUID?>)
    private struct SelectedSectionIDKey: FocusedValueKey {
        typealias Value = Binding<UUID?>
    }
    var selectedSectionID: Binding<UUID?>? {
        get { self[SelectedSectionIDKey.self] }
        set { self[SelectedSectionIDKey.self] = newValue }
    }

    // 3) A key for showing the delete confirmation
    private struct ShowDeleteAlertKey: FocusedValueKey {
        typealias Value = Binding<Bool>
    }
    var showDeleteAlert: Binding<Bool>? {
        get { self[ShowDeleteAlertKey.self] }
        set { self[ShowDeleteAlertKey.self] = newValue }
    }

}

extension NSAttributedString {
    /// Return the attribute dictionary at character index 0,
    /// or if that fails, return a default [font: systemFont(12), color: labelColor].
    func defaultAttributes() -> [NSAttributedString.Key: Any] {
        guard length > 0 else {
            return [
                .font: PlatformFont.systemFont(ofSize: 12),
                .foregroundColor: PlatformColor.label
            ]
        }
        return attributes(at: 0, effectiveRange: nil)
    }
}
