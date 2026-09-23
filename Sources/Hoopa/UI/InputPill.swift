import SwiftUI

/// The input pill: [⌖ bind] [◔ time] type a to-do… The binding and the time can be chosen before typing the text.
struct InputPill: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var title = ""
    @State private var showDue = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            bindChip
            dueChip
            TextField("Add a to-do, Return creates it", text: $title)
                .textFieldStyle(.plain)
                .foregroundStyle(Style.text)
                .focused($focused)
                .onSubmit(submit)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Style.card))
        .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private var bindChip: some View {
        Group {
            if let b = coordinator.pendingBinding {
                HStack(spacing: 4) {
                    BindingChip(binding: b)
                    Button { coordinator.pendingBinding = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Style.secondary)
                }
                .help("Will be bound to: \(b.detailDescription)")
            } else {
                Button { coordinator.pickPendingBinding() } label: {
                    Image(systemName: "scope").foregroundStyle(Style.accent)
                }
                .buttonStyle(.plain)
                .chip()
                .help("Choose the window / page to bind first, then type the content")
            }
        }
    }

    private var dueChip: some View {
        Button { showDue.toggle() } label: {
            if let d = coordinator.pendingDue {
                DueChip(due: d, showDetail: false)
            } else {
                Image(systemName: "timer").foregroundStyle(Style.secondary).chip()
            }
        }
        .buttonStyle(.plain)
        .help("Countdown / date")
        .popover(isPresented: $showDue) {
            DuePicker(due: $coordinator.pendingDue) { showDue = false }
        }
    }

    private func submit() {
        guard store.add(title, binding: coordinator.pendingBinding, due: coordinator.pendingDue) != nil else { return }
        title = ""
        coordinator.pendingBinding = nil
        coordinator.pendingDue = nil
        focused = true
    }
}
