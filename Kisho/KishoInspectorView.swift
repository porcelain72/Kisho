/*import SwiftUI
import AppKit

/// Inspector pane for a single KishoSection.
/// Shows typography controls (font family/size/bold/italic/color) and a tag‐entry field.
struct KishoInspectorView: View {
    @ObservedObject var section: KishoSection

    // MARK: –– “Focus these only once when view appears”
    @State private var hasLoadedInitialValues = false

    // MARK: –– Font & style state
    @State private var fontFamilies: [String] = []
    @State private var selectedFontFamily: String = NSFont.systemFont(ofSize: 12).familyName ?? "System"
    @State private var fontSize: Double = 12
    @State private var isBold: Bool = false
    @State private var isItalic: Bool = false
    @State private var textColor: Color = .primary

    // MARK: –– Tags field (comma‐separated)
    @State private var tagString: String = ""

    var body: some View {
        Form {
            // ─── Typography Section ─────────────────────────────────────────
            Section(header: Text("Typography")) {
                // Font family picker
                Picker("Font Family", selection: $selectedFontFamily) {
                    ForEach(fontFamilies, id: \.self) { fam in
                        Text(fam).font(.custom(fam, size: 13))
                    }
                }
                .labelsHidden()
                .help("Choose a font.")

                // Font size stepper
                HStack {
                    Text("Size")
                    Spacer()
                    Stepper(value: $fontSize, in: 8...72, step: 1) {
                        Text("\(Int(fontSize)) pt")
                            .frame(width:  40.0, alignment: .trailing) // fixed‐width so it doesn’t jump
                    }
                    .help("Choose font size.")
                }

                // Bold / Italic toggles
                Toggle("Bold", isOn: $isBold)
                    .help("Toggle bold style.")
                Toggle("Italic", isOn: $isItalic)
                    .help("Toggle italic style.")

                // Color picker
                ColorPicker("Color", selection: $textColor)
                    .help("Choose a text color.")
            }

            // ─── Tags Section ────────────────────────────────────────────────
            Section(header: Text("Tags")) {
                TextField("tag1, tag2, tag3", text: $tagString, onCommit: commitTags)
                    .help("Enter comma-separated tags for this section.")
            }
        }
     //   Text("Insoectorrrr")
        .padding()
        .frame(minWidth: 250) // adjust as desired
        .onAppear {
            // Populate the list of available font families once
            if !hasLoadedInitialValues {
                fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()
                DispatchQueue.main.async{
                    loadCurrentValuesFromSection()
                    hasLoadedInitialValues = true
                }
            }
        }
        // Whenever any of these style properties change, reapply to the section’s text:
        .onChange(of: selectedFontFamily) { _ in applyTypographyToSection() }
        .onChange(of: fontSize) { _ in applyTypographyToSection() }
        .onChange(of: isBold) { _ in applyTypographyToSection() }
        .onChange(of: isItalic) { _ in applyTypographyToSection() }
        .onChange(of: textColor) { _ in applyTypographyToSection() }
        // Whenever the user edits the tag string, push it back to section.tags
        .onChange(of: tagString) { _ in commitTags() }
    }

    // MARK: –– Helpers

    /// Read the section’s current attributes (if any) and initialize our state fields.
    private func loadCurrentValuesFromSection() {
        let attributed = section.attributedText  // KishoRichText wraps an NSAttributedString internally
        let fullRange = NSRange(location: 0, length: attributed.length)

        // If there is at least one attribute run, read its font/color
        if attributed.length > 0,
           let firstFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        {
            selectedFontFamily = firstFont.familyName ?? selectedFontFamily
            fontSize = Double(firstFont.pointSize)
            isBold = firstFont.fontDescriptor.symbolicTraits.contains(.bold)
            isItalic = firstFont.fontDescriptor.symbolicTraits.contains(.italic)
            
            
            if let firstColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor {
                // Convert NSColor to SwiftUI Color
                textColor = Color(firstColor)
            }
        }
        // Initialize tags
        tagString = section.tags.joined(separator: ", ")
    }

    /// Take the current state of font family/size/bold/italic/color and reapply it to
    /// the entire contents of `section.attributedText` (overwriting any previous attributes).
    ///
    /// // In InspectorView:
    @State private var lastAppliedAttributes: (family: String, size: Double, bold: Bool, italic: Bool, color: Color)?

    private func applyTypographyToSection() {
        let snapshot = (selectedFontFamily, fontSize, isBold, isItalic, textColor, section.attributedText.string)
        DispatchQueue.global(qos: .userInitiated).async {
            let (family, size, bold, italic, color, text) = snapshot
            let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
                .withSymbolicTraits([
                    bold ? .bold : [],
                    italic ? .italic : []
                ]) ?? NSFontDescriptor(fontAttributes: [.family: family])
            let font = NSFont(descriptor: descriptor, size: CGFloat(size)) ?? NSFont.systemFont(ofSize: CGFloat(size))
            let nsColor = NSColor(color)
            
            let newAttributed = NSMutableAttributedString(string: text)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: nsColor
            ]
            newAttributed.addAttributes(attrs, range: NSRange(location: 0, length: newAttributed.length))

            DispatchQueue.main.async {
                // Only assign if nothing else changed in the meantime
                if self.selectedFontFamily == family
                   && self.fontSize == size
                   && self.isBold == bold
                   && self.isItalic == italic
                   && self.textColor == color
                {
                    self.section.attributedText = newAttributed
                }
            }
        }
    }

    /*
    private func applyTypographyToSection() {
        let fullText = section.attributedText.string
        let newAttributed = NSMutableAttributedString(string: fullText)

        // Build the NSFontDescriptor
        var descriptor = NSFontDescriptor(fontAttributes: [.family: selectedFontFamily])
        var traits = NSFontDescriptor.SymbolicTraits()
        if isBold { traits.insert(.bold) }
        if isItalic { traits.insert(.italic) }
        descriptor = descriptor.withSymbolicTraits(traits) ?? descriptor

        // Create the NSFont
        let font = NSFont(descriptor: descriptor, size: CGFloat(fontSize)) ??
                   NSFont.systemFont(ofSize: CGFloat(fontSize))

        // Build attribute dictionary
        let nsColor = NSColor(textColor)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: nsColor
        ]

        // Apply to entire range
        newAttributed.addAttributes(attrs, range: NSRange(location: 0, length: newAttributed.length))

        // Commit back to the section
        section.attributedText = newAttributed
    }
*/
    /// Parse `tagString` (comma-separated) and push into `section.tags`.
    private func commitTags() {
        let split = tagString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        section.tags = split
    }
}
*/

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif


#if os(macOS)

/// A classic‐style macOS Inspector for a KishoSection.
/// - Appears as a narrow, scrollable vertical panel.
/// - Uses GroupBoxes for “Typography” and “Tags” sections.
/// - Applies a subtle NSVisualEffectMaterial.sidebar background.
/// - Constrains itself to a fixed width and scrolls if necessary.
struct KishoInspectorView: View {
    @ObservedObject var section: KishoSection

    // MARK: –– One‐time initialization flags
    @State private var didLoadDefaults = false

    // MARK: –– Typography state
    @State private var fontFamilies: [String] = []
    #if os(macOS)
    @State private var selectedFontFamily: String = NSFont.systemFont(ofSize: 12).familyName ?? "System"
    #else
    @State private var selectedFontFamily: String = UIFont.systemFont(ofSize: 12).familyName ?? "System"

    #endif
    @State private var fontSize: Double = 12
    @State private var isBold: Bool = false
    @State private var isItalic: Bool = false
    @State private var textColor: Color = .primary

    // MARK: –– Tags state
    @State private var tagString: String = ""

    var body: some View {
        // Use a VisualEffect background to mimic a sidebar inspector
        ScrollView {
            VStack(spacing: 16) {
                // ─── Typography GroupBox ───────────────────────────
                GroupBox(label: Text("Typography").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Font Family Picker
                        Picker("Font Family", selection: $selectedFontFamily) {
                            ForEach(fontFamilies, id: \.self) { fam in
                                Text(fam).font(.custom(fam, size: 13))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                        // Font Size Stepper
                        HStack {
                            Text("Size")
                            Spacer()
                            Stepper(value: $fontSize, in: 8...72, step: 1) {
                                Text("\(Int(fontSize)) pt")
                                    .frame(width:  40.0, alignment: .trailing)
                            }
                        }

                        // Bold / Italic Toggles
                        Toggle("Bold", isOn: $isBold)
                        Toggle("Italic", isOn: $isItalic)

                        // Color Picker
                        ColorPicker("Color", selection: $textColor)
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal)

                // ─── Tags GroupBox ──────────────────────────────────
                GroupBox(label: Text("Tags").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("tag1, tag2, tag3", text: $tagString, onCommit: commitTags)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal)

                Spacer(minLength: 20)
            }
            .padding(.top, 16)
            .frame(maxWidth: .infinity)
        }
        .background(
            // Use the macOS “sidebar” material so it blends with the window
            VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
                .ignoresSafeArea()
        
        )
   
        // Constrain inspector’s width so it never expands too far
        .frame(minWidth: 250, idealWidth: 300, maxWidth: 350)
        .onAppear {
            guard !didLoadDefaults else { return }
            didLoadDefaults = true
            // Populate font families once
            fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()
         
            // Load initial typography from section.content
            loadCurrentValuesFromSection()

            // Load initial tags
            tagString = section.tags.joined(separator: ", ")
        }
        .onChange(of: selectedFontFamily) { _ in applyTypographyToSection() }
        .onChange(of: fontSize) { _ in applyTypographyToSection() }
        .onChange(of: isBold) { _ in applyTypographyToSection() }
        .onChange(of: isItalic) { _ in applyTypographyToSection() }
        .onChange(of: textColor) { _ in applyTypographyToSection() }
        .onChange(of: tagString) { _ in commitTags() }
    }

    // MARK: –– Load the section’s existing font/color into state
    private func loadCurrentValuesFromSection() {
        let attributed = section.content.attributedString
        let fullLength = attributed.length
        guard fullLength > 0 else { return }

        if let firstFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            selectedFontFamily = firstFont.familyName ?? selectedFontFamily
            fontSize = Double(firstFont.pointSize)
            let traits = firstFont.fontDescriptor.symbolicTraits
            isBold = traits.contains(.bold)
            isItalic = traits.contains(.italic)
        }
        if let firstColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor {
            textColor = Color(firstColor)
        }
    }

    // MARK: –– Apply all typography state to the entire section string
    private func applyTypographyToSection() {
        let fullText = section.content.attributedString.string
        let newAttributed = NSMutableAttributedString(string: fullText)
print(fontSize)
        // Build font descriptor
        var descriptor = NSFontDescriptor(fontAttributes: [.family: selectedFontFamily])
        var traits = NSFontDescriptor.SymbolicTraits()
        if isBold { traits.insert(.bold) }
        if isItalic { traits.insert(.italic) }
        descriptor = descriptor.withSymbolicTraits(traits) ?? descriptor

        // Create NSFont
        let nsFont = NSFont(descriptor: descriptor, size: CGFloat(fontSize))
            ?? NSFont.systemFont(ofSize: CGFloat(fontSize))

        // Build attribute dictionary
        let nsColor = NSColor(textColor)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .foregroundColor: nsColor
        ]
        newAttributed.addAttributes(attrs, range: NSRange(location: 0, length: newAttributed.length))

        // Assign back to the section (Published → autosave)
      //  section.content.attributes = attrs
        section.content.attributedString = newAttributed
        section.inspectorVersion = UUID()
    }

    // MARK: –– Parse tagString into section.tags
    private func commitTags() {
        let split = tagString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        section.tags = split
    }
}

/// A helper NSViewRepresentable that wraps NSVisualEffectView
/// so we can use macOS 11+ materials in SwiftUI.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// A small helper so you can call `NSColor(some Color)`
extension NSColor {
    convenience init(_ color: Color) {
        let scanner = Scanner(string: color.description.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hex: UInt64 = 0
        scanner.scanHexInt64(&hex)
        let r = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hex & 0x00FF00) >> 8)  / 255.0
        let b = CGFloat(hex & 0x0000FF)         / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}



#endif
