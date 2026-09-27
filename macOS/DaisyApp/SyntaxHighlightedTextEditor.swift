import SwiftUI
import AppKit

// MARK: - JSON Highlighter

private enum JSONHighlighter {
    // Order matters: keys are applied last to overwrite string coloring
    private static let patterns: [(NSRegularExpression, (NSAppearance?) -> NSColor)] = {
        let defs: [(String, (NSAppearance?) -> NSColor)] = [
            // Strings (including escaped quotes)
            (#""(?:[^"\\]|\\.)*""#, { _ in .systemGreen }),
            // Numbers
            (#"(?<!["\w])-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?(?!["\w])"#, { _ in .systemCyan }),
            // Booleans
            (#"\b(?:true|false)\b"#, { _ in .systemPurple }),
            // Null
            (#"\bnull\b"#, { _ in .systemRed }),
            // Keys ("key":) — applied last to overwrite green
            (#""(?:[^"\\]|\\.)*"\s*(?=:)"#, { _ in .systemOrange }),
        ]
        return defs.map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
    }()

    static func highlight(_ textStorage: NSTextStorage, font: NSFont, appearance: NSAppearance?) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string

        // Reset to default
        textStorage.beginEditing()
        textStorage.addAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ], range: fullRange)

        // Apply each pattern
        for (regex, colorFn) in patterns {
            let color = colorFn(appearance)
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let range = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: color, range: range)
                }
            }
        }
        textStorage.endEditing()
    }
}

// MARK: - NSViewRepresentable

struct SyntaxHighlightedTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true

        // Disable smart substitutions (critical for JSON)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        textView.font = font
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = .textBackgroundColor

        // Allow horizontal scrolling for long lines
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        // Set initial text
        context.coordinator.isUpdating = true
        textView.string = text
        if let ts = textView.textStorage {
            JSONHighlighter.highlight(ts, font: font, appearance: textView.effectiveAppearance)
        }
        context.coordinator.isUpdating = false

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard !context.coordinator.isUpdating else { return }

        if textView.string != text {
            context.coordinator.isUpdating = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            if let ts = textView.textStorage {
                JSONHighlighter.highlight(ts, font: font, appearance: textView.effectiveAppearance)
            }
            textView.selectedRanges = selectedRanges
            context.coordinator.isUpdating = false
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxHighlightedTextEditor
        var isUpdating = false

        init(_ parent: SyntaxHighlightedTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating else { return }
            guard let textView = notification.object as? NSTextView else { return }

            isUpdating = true
            parent.text = textView.string
            if let ts = textView.textStorage {
                JSONHighlighter.highlight(ts, font: parent.font, appearance: textView.effectiveAppearance)
            }
            isUpdating = false
        }
    }
}
