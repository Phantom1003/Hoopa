import SwiftUI

/// A multi-line field that grows with its content: Return inserts a newline, ⌘Return submits.
struct GrowingTextEditor: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey
    var font: Font = .system(size: 13)
    var maxHeight: CGFloat = 140
    var onCommit: () -> Void
    @FocusState.Binding var focused: Bool

    var body: some View {
        // A hidden copy of the text sets the height so the editor grows with its content; it also provides the first line's baseline, so the done box next to it can align with the first line
        // (the editor is AppKit, SwiftUI cannot read its baseline). The editor and the placeholder sit on top of it at the same size.
        Text(text.isEmpty ? " " : text + (text.hasSuffix("\n") ? " " : ""))
            .font(font)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .frame(maxHeight: maxHeight, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(font)
                            .foregroundStyle(Style.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(font)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .padding(.horizontal, 0)
                        .focused($focused)
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.command) {
                                onCommit()
                                return .handled
                            }
                            return .ignored
                        }
                }
            }
    }
}
