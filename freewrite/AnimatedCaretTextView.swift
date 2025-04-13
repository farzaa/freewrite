import SwiftUI
import AppKit

struct AnimatedCaretTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedFont: String
    @Binding var fontSize: CGFloat
    var placeholder: String // Add placeholder property

    // Coordinator class to handle text view delegate methods
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AnimatedCaretTextView
        var placeholderLabel: NSTextField? // Label to show placeholder

        init(_ parent: AnimatedCaretTextView) {
            self.parent = parent
        }

        // Update the parent's text binding when the text view content changes
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            // Show/hide placeholder based on text content
            placeholderLabel?.isHidden = !textView.string.isEmpty
        }

        // Optional: Handle selection changes if needed
        func textViewDidChangeSelection(_ notification: Notification) {
            // You could add logic here if selection changes need to trigger updates
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false // Hide vertical scroll bar
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear // Ensure scroll view background is clear

        let textView = CustomTextView() // Use CustomTextView
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false // Work with plain text
        textView.allowsUndo = true
        textView.backgroundColor = .clear // Ensure text view background is clear
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true // Important for wrapping

        // Set initial font and size
        let font = NSFont(name: selectedFont, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        textView.font = font
        textView.textColor = NSColor(Color(red: 0.20, green: 0.20, blue: 0.20)) // Set text color

        // Configure insertion point (caret) color and blinking
        textView.insertionPointColor = NSColor.black // Set caret color
        // Blinking is usually handled by the system, but ensure it's enabled if needed
        // textView.setInsertionPointBlinking(enabled: true) // This method doesn't exist directly, blinking is default

        // Add placeholder label
        let placeholderLabel = NSTextField(labelWithString: placeholder)
        placeholderLabel.font = font // Use the same font as the text view
        placeholderLabel.textColor = NSColor.placeholderTextColor
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.backgroundColor = .clear
        placeholderLabel.maximumNumberOfLines = 0 // Allow wrapping
        placeholderLabel.lineBreakMode = .byWordWrapping

        textView.addSubview(placeholderLabel)
        context.coordinator.placeholderLabel = placeholderLabel

        // Constraints for placeholder (adjust padding as needed)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 0), // Align top
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: textView.textContainerInset.width + 5), // Align leading with padding
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -(textView.textContainerInset.width + 5)), // Allow space on trailing edge
             placeholderLabel.widthAnchor.constraint(lessThanOrEqualTo: textView.widthAnchor, constant: -2 * (textView.textContainerInset.width + 5)) // Constrain width
        ])

        // Set initial text and placeholder visibility
        textView.string = text
        placeholderLabel.isHidden = !text.isEmpty

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CustomTextView else { return }

        // Update font and size if they changed
        let newFont = NSFont(name: selectedFont, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        if textView.font != newFont {
            textView.font = newFont
            // Update placeholder font too
            context.coordinator.placeholderLabel?.font = newFont
        }

        // Update text content if it changed externally (e.g., loading a new entry)
        // Check prevents infinite loop with textDidChange
        if textView.string != text {
            // Preserve cursor position if possible
            let selectedRange = textView.selectedRange()
            textView.string = text
            // Try to restore cursor position, clamp if out of bounds
            let newLength = text.count
            let newRange = NSRange(location: min(selectedRange.location, newLength), length: 0)
            textView.setSelectedRange(newRange)

            // Update placeholder visibility after text update
            context.coordinator.placeholderLabel?.isHidden = !text.isEmpty
        }

         // Update placeholder text if it changed
        if context.coordinator.placeholderLabel?.stringValue != placeholder {
            context.coordinator.placeholderLabel?.stringValue = placeholder
        }

        // Ensure caret color remains correct (might be reset sometimes)
        if textView.insertionPointColor != NSColor.black {
            textView.insertionPointColor = NSColor.black
        }
    }
}

// Custom NSTextView subclass to potentially override drawing or behavior
class CustomTextView: NSTextView {
    // Override drawInsertionPoint to customize caret appearance if needed
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // Use the default color passed, which we set to black in makeNSView/updateNSView
        super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
    }

    // Override other methods if necessary, e.g., for smoother scrolling or layout
    override func layout() {
        super.layout()
        // Custom layout adjustments if needed
    }
}
