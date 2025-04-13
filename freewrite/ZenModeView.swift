import SwiftUI

struct ZenModeView: View {
    @Binding var currentLine: String
    @Binding var previousLines: [String]
    @Binding var text: String // To update the main text model
    @Binding var selectedFont: String
    @Binding var fontSize: CGFloat
    @Binding var timeRemaining: Int
    @Binding var timerIsRunning: Bool
    @Binding var isZenMode: Bool // To allow exiting from within? (Maybe not needed)

    // State for the temporary prompt
    @State private var showZenPrompt: Bool = true

    // Computed property for timer display
    var timerButtonTitle: String {
        if !timerIsRunning && timeRemaining == 900 { // Assuming 900 is the default
            return "" // Don't show if timer isn't running and is at default
        }
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // Computed property for dynamic font size
    var zenFontSize: CGFloat {
        return fontSize * 2.2 // Make it significantly larger (Increased multiplier)
    }

    var body: some View {
        ZStack { // Use ZStack to overlay the prompt
            Color.white
                .ignoresSafeArea()

            // Main content VStack
            VStack {
                Spacer()

                TextField("", text: $currentLine)
                    .font(.custom(selectedFont, size: zenFontSize))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(Color(red: 0.20, green: 0.20, blue: 0.20))
                    .padding(.horizontal, 40) // Add some horizontal padding
                    .onSubmit {
                        // When Enter is pressed
                        let trimmedLine = currentLine.trimmingCharacters(in: .whitespaces)
                        if !trimmedLine.isEmpty {
                            previousLines.append(currentLine) // Append the original line to preserve spacing if intended
                        }
                        // Update the main text state
                        // Ensure consistent newline handling, maybe add only one newline between blocks
                        text = previousLines.joined(separator: "\n") + (previousLines.isEmpty ? "" : "\n")
                        currentLine = "" // Clear for the next line
                    }

                Spacer()

                // Timer display in Zen mode
                if timerIsRunning || timeRemaining != 900 { // Show if running or not at default
                    Text(timerButtonTitle)
                        .font(.system(size: 18)) // Larger timer size
                        .foregroundColor(.gray.opacity(0.8))
                        .padding(.bottom, 30) // More padding from bottom
                }
            } // End VStack

            // Temporary Zen Prompt Overlay
            if showZenPrompt {
                Text("Zen Mode. Just write.")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.gray.opacity(0.6))
                    .transition(.opacity.animation(.easeOut(duration: 0.5))) // Fade transition
                    .allowsHitTesting(false) // Prevent prompt from blocking TextField
            }

            // Invisible button to handle Escape key press
            Button("") {
                withAnimation {
                    isZenMode = false // Exit Zen mode
                }
            }
            .keyboardShortcut(.escape, modifiers: []) // Assign Escape key
            .opacity(0) // Make it invisible
            .allowsHitTesting(false) // Ensure it doesn't interfere with clicks

        } // End ZStack
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it fills the space
        .onAppear {
            // Reset prompt state on appear
            showZenPrompt = true
            // Schedule prompt fade-out after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    showZenPrompt = false
                }
            }
        }
    }
}

// Add a preview provider if needed (optional)
#Preview {
    // Need to provide mock bindings for preview
    @State var mockLine = "This is the current line."
    @State var mockPrevious: [String] = ["Line 1", "Line 2"]
    @State var mockText = "Line 1\nLine 2\nThis is the current line."
    @State var mockFont = "Lato-Regular"
    @State var mockFontSize: CGFloat = 18
    @State var mockTime = 850
    @State var mockIsRunning = true
    @State var mockIsZen = true

    return ZenModeView(
        currentLine: $mockLine,
        previousLines: $mockPrevious,
        text: $mockText,
        selectedFont: $mockFont,
        fontSize: $mockFontSize,
        timeRemaining: $mockTime,
        timerIsRunning: $mockIsRunning,
        isZenMode: $mockIsZen
    )
}
