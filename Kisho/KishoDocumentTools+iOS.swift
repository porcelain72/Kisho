//
//  KishoDocumentTools+iOS.swift
//  Kisho
//
//  The document tools on iOS that the Mac keeps in menus and panels: the
//  find & replace bar, export through the share sheet, import through the
//  file importer, printing, and the in-app Settings sheet (the same
//  UserDefaults keys as the Mac's Settings window).
//

#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Find bar

/// Find & replace across every block, shown above the cards. Matching and
/// replacing are the model's (shared with the Mac); this is the control.
struct FindBar: View {
    @EnvironmentObject var document: KishoDocumentModel
    @ObservedObject var find: FindState
    @Environment(\.undoManager) private var undoManager
    @FocusState private var queryFocused: Bool
    @State private var showReplace = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find", text: $find.query)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($queryFocused)
                    .onSubmit { find.step(forward: true) }
                Text(find.summary)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Button { find.step(forward: false) } label: { Image(systemName: "chevron.up") }
                    .disabled(find.matches.isEmpty)
                Button { find.step(forward: true) } label: { Image(systemName: "chevron.down") }
                    .disabled(find.matches.isEmpty)
                Menu {
                    Toggle("Match Case", isOn: $find.matchCase)
                    Toggle("Replace", isOn: $showReplace)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button { find.hide() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Close Find")
            }
            if showReplace {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                    TextField("Replace", text: $find.replacement)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onSubmit { find.replaceCurrent(using: undoManager) }
                    Button("Replace") { find.replaceCurrent(using: undoManager) }
                        .disabled(find.matches.isEmpty)
                    Button("All") { find.replaceAll(using: undoManager) }
                        .disabled(find.matches.isEmpty)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear {
            find.attach(to: document)
            find.refresh()
            if find.pendingFocus {
                find.pendingFocus = false
                queryFocused = true
            }
        }
        .onChange(of: find.focusToken) { _ in queryFocused = true }
        .onChange(of: find.query) { _ in find.refresh() }
        .onChange(of: find.matchCase) { _ in find.refresh() }
    }
}

// MARK: - Export, import, print

/// Export the document in a format and hand the file to the share sheet.
enum DocumentExport {
    /// Writes the converted document to a temporary file named after the
    /// document, or nil when the conversion fails.
    static func file(for document: KishoDocumentModel, as format: Exporter.Format, title: String) -> URL? {
        guard let data = Exporter.data(for: document, as: format, title: title) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KishoExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeTitle = title.replacingOccurrences(of: "/", with: "-")
        let url = folder.appendingPathComponent("\(safeTitle).\(format.fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// The system print panel with the same paged PDF as Export ▸ PDF.
    static func print(_ document: KishoDocumentModel, title: String) {
        guard let data = Exporter.data(for: document, as: .pdf, title: title),
              UIPrintInteractionController.canPrint(data) else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = title
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true)
    }
}

/// The system share sheet for one file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// What a file importer brought in: the parsed sections and typography,
/// or an error to show.
enum DocumentImportResult {
    case document(KishoDocumentModel)
    case failure(String)

    /// Parse a Markdown or OPML file (by its type, then its extension).
    static func read(_ url: URL) -> DocumentImportResult {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let type = UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .opml) == true || url.pathExtension.lowercased() == "opml" || type?.conforms(to: .xml) == true {
                let typography = KishoPreferences.defaultTypography
                let sections = try OPML.sections(from: Data(contentsOf: url), typography: typography)
                let model = KishoDocumentModel(sections: sections)
                model.typography = typography
                return .document(model)
            }
            let text = try String(contentsOf: url)
            let imported = Markdown.document(from: text)
            let model = KishoDocumentModel(sections: imported.sections)
            model.typography = imported.typography
            return .document(model)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

// MARK: - Settings

/// In-app Settings (the Mac has a Settings window with the same keys):
/// defaults for new documents, editing habits, the editor's look, print.
struct KishoSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(KishoPreferences.Key.defaultFontFamily) private var fontFamily = TypographySettings.defaultFontFamily
    @AppStorage(KishoPreferences.Key.defaultFontSize) private var fontSize = TypographySettings.defaultFontSize
    @AppStorage(KishoPreferences.Key.newBlockFocusesBody) private var newBlockFocusesBody = false
    @AppStorage(KishoPreferences.Key.printMargins) private var printMargins = KishoPreferences.PrintMargins.normal.rawValue
    @AppStorage(KishoPreferences.Key.editorTheme) private var editorTheme = EditorTheme.system.rawValue
    @AppStorage(KishoPreferences.Key.typewriterScrolling) private var typewriter = false
    @AppStorage(KishoPreferences.Key.showSynopses) private var showSynopses = false

    @State private var families: [String] = []
    private let sizes: [Double] = [10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Settings") { dismiss() }
            Form {
                Section {
                    Picker("Font", selection: $fontFamily) {
                        ForEach(families, id: \.self) { family in
                            Text(TypographySettings.displayName(forFamily: family)).tag(family)
                        }
                    }
                    Picker("Size", selection: $fontSize) {
                        ForEach(sizes, id: \.self) { size in
                            Text("\(Int(size)) pt").tag(size)
                        }
                    }
                } header: {
                    Text("New documents")
                } footer: {
                    Text("Existing documents keep their own font; change it in the inspector.")
                }

                Section {
                    Picker("New blocks start in", selection: $newBlockFocusesBody) {
                        Text("Title").tag(false)
                        Text("Body").tag(true)
                    }
                    Toggle("Typewriter scrolling", isOn: $typewriter)
                    Toggle("Show synopses in outline", isOn: $showSynopses)
                } header: {
                    Text("Editing")
                } footer: {
                    Text("Typewriter scrolling keeps the line you are typing near the middle of the screen.")
                }

                Section("Editor theme") {
                    Picker("Theme", selection: $editorTheme) {
                        ForEach(EditorTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }
                }

                Section {
                    Picker("Margins", selection: $printMargins) {
                        ForEach(KishoPreferences.PrintMargins.allCases) { margins in
                            Text(margins.title).tag(margins.rawValue)
                        }
                    }
                } header: {
                    Text("Print and PDF")
                } footer: {
                    Text("Paper is A4 or Letter by your region.")
                }
            }
        }
        .onAppear {
            var list = PlatformFont.availableFamilyNames.sorted()
            if !list.contains(fontFamily) { list.insert(fontFamily, at: 0) }
            families = list
            if !sizes.contains(fontSize) { fontSize = TypographySettings.defaultFontSize }
        }
    }
}
#endif
