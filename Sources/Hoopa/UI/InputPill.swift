import SwiftUI

/// The composer for a new to-do: hidden by default, the + at the top right of the panel or the + ball in the collapsed list brings it up at the top of the list (always shown when there are no to-dos at all).
/// One line of title, Return submits (the notes are filled in after opening the to-do); the second row chooses the binding and time first. A countdown starts ticking only at submission. Esc or the × on the right closes it.
struct InputPill: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var title = ""
    @State private var showDue = false
    @FocusState private var focused: Bool

    /// Any one of title, binding or time is enough to submit.
    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || coordinator.pendingBinding != nil || coordinator.pendingDue != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("Add a to-do…", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit(submit)
                    .onKeyPress(.escape) { close(); return .handled }
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Style.secondary)
                        .frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            HStack(spacing: 6) {
                bindChip
                dueChip
                Spacer(minLength: 0)
                // The submit button: the same capsule language as the chips, lit only when there is content.
                submitButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // The field's look: outline only, no fill, distinct from the filled to-do cards below.
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.14)))
        .onAppear { if !coordinator.isCompact { DispatchQueue.main.async { focused = true } } }
        // Collapsed, the panel stays off-window, so take the focus back or keys would land in the invisible field; close the composer too if nothing was entered.
        .onChange(of: coordinator.isCompact) { _, compact in
            if compact {
                focused = false
                if !canSubmit { coordinator.adding = false }
            } else {
                DispatchQueue.main.async { focused = true }
            }
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(canSubmit ? Color.white : Style.tertiary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(canSubmit ? Style.accent : Style.chip))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .keyboardShortcut(.return, modifiers: .command)
        .animation(.easeOut(duration: 0.15), value: canSubmit)
        .help("Add (Return)")
    }

    private var bindChip: some View {
        Group {
            if let b = coordinator.pendingBinding {
                selectedChip(clear: { coordinator.pendingBinding = nil },
                             reselect: { coordinator.pickPendingBinding() },
                             help: String(localized: "Will bind to:\n\(b.detailDescription)\nClick to choose again")) {
                    BindingChip(binding: b, bare: true)
                }
            } else {
                Button { coordinator.pickPendingBinding() } label: {
                    fitting(Label("Bind Window / Page", systemImage: "scope"), icon: "scope").foregroundStyle(Style.secondary)
                }
                .buttonStyle(.plain)
                .chip()
                .help("Pick the window / page to bind, then type the to-do")
            }
        }
    }

    private var dueChip: some View {
        Group {
            if let sp = coordinator.pendingDue {
                selectedChip(clear: { coordinator.pendingDue = nil },
                             reselect: { showDue.toggle() },
                             help: String(localized: "Click to choose again")) {
                    SpecChip(spec: sp, bare: true)
                }
            } else {
                Button { showDue.toggle() } label: {
                    fitting(Label("Timer / Date", systemImage: "timer"), icon: "timer").foregroundStyle(Style.secondary)
                }
                .buttonStyle(.plain)
                .chip()
                .help("Timer / date")
            }
        }
        .popover(isPresented: $showDue, arrowEdge: .bottom) {
            DuePicker(spec: $coordinator.pendingDue) { showDue = false }
        }
    }

    /// When the panel is narrow and the text does not fit, show the icon only (rather than truncating to "Bind Win…").
    private func fitting<L: View>(_ label: L, icon: String) -> some View {
        ViewThatFits(in: .horizontal) {
            label
            Image(systemName: icon)
        }
    }

    /// The chosen chip: × on the left (clear), a click on the chip itself chooses again.
    private func selectedChip<Content: View>(clear: @escaping () -> Void, reselect: @escaping () -> Void,
                                             help: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Button(action: clear) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Style.secondary)
                    .frame(width: 12, height: 12).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Clear")
            Button(action: reselect) { content().contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .help(help)
        }
        .chip()
    }

    private func submit() {
        guard canSubmit,
              store.add(title, binding: coordinator.pendingBinding, due: coordinator.pendingDue?.resolve()) != nil else { return }
        title = ""
        coordinator.pendingBinding = nil
        coordinator.pendingDue = nil
        focused = true
    }

    /// Closes the composer, dropping the unsubmitted title and the chosen binding and time.
    private func close() {
        title = ""
        coordinator.pendingBinding = nil
        coordinator.pendingDue = nil
        coordinator.adding = false
    }
}
