import AppKit
import Combine

/// How far the collapsed state is unfolded: pill → card → card stack.
enum CompactStage: Int, Comparable {
    case pill, card, stack
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// The bridge between the UI and the AppKit layer: binding, jumping, toasts, collapse / expand.
final class AppCoordinator: ObservableObject {
    @Published var jumpingID: UUID?
    @Published var toast: String?
    @Published var isPicking = false
    @Published var alwaysOnTop = true
    /// Collapsed (only the most urgent to-do showing).
    @Published var isCompact = false {
        willSet {
            // Grow / shrink the window before the state changes: SwiftUI lays out once with the new window size and the old state (without animation),
            // then the state changes and animates. Otherwise the root view's size change joins the animation as a geometry animation about the centre and drags the plate off.
            if newValue != isCompact { onCompactChanged?(newValue) }
        }
        didSet {
            guard oldValue != isCompact else { return }
            stageWork?.cancel()
            if !isCompact {
                hoveringCompact = false
            } else if restoring {
                stage = .pill; stageTarget = .pill
            } else {
                // The panel shrinks back to the front card; once shrunk, the cards behind appear if the mouse is on it, otherwise it folds into the pill.
                stage = .card; stageTarget = .card
                stageWork = after(Motion.collapseBusy) { [weak self] in
                    guard let self else { return }
                    self.moveStage(to: self.hoveringCompact ? .stack : .pill)
                }
            }
        }
    }
    /// What the collapsed state currently looks like; changes step by step on mouse enter / exit (see moveStage).
    @Published private(set) var stage: CompactStage = .pill
    /// The size of the window's content area (reported by FloatingPanel): the expanded panel's plate fills it.
    @Published var panelSize = CGSize(width: 360, height: 480)
    /// The binding and time "chosen but not yet created" in the composer.
    @Published var pendingBinding: ContextBinding?
    @Published var pendingDue: DueSpec?

    /// Pick: nil means picking for the to-do about to be created in the composer.
    var onStartPicking: ((TodoItem?) -> Void)?
    var onAlwaysOnTopChanged: ((Bool) -> Void)?
    var onCompactChanged: ((Bool) -> Void)?
    /// The collapsed state starts morphing: how long the animation takes (the window only grows during it, the shadow keeps refreshing) and the content size at the end (the window grows to it right away).
    var onMorph: ((TimeInterval, CGSize?) -> Void)?
    /// The overall size of each collapsed stage, reported by CompactView (not published: only the window uses it).
    var compactSizes = CompactSizes()
    var onQuit: (() -> Void)?

    private var toastToken = 0
    private var stageTarget: CompactStage = .pill
    private var stageWork: DispatchWorkItem?
    private var hoveringCompact = false
    private var restoring = false

    /// Launch straight into the pill: no animation, no pass through the card stack.
    func restoreCompact() {
        restoring = true
        isCompact = true
        restoring = false
    }

    /// Mouse enter / exit while collapsed: the pill becomes a card first, then the cards behind appear; exiting reverses it.
    func hoverCompact(_ inside: Bool) {
        hoveringCompact = inside
        moveStage(to: inside ? .stack : .pill)
    }

    private func moveStage(to target: CompactStage) {
        guard target != stageTarget else { return }   // already heading that way, do not interrupt the step being played
        stageTarget = target
        stageWork?.cancel()
        stepStage()
    }

    /// One step towards the target, the next one after Motion.stepGap.
    private func stepStage() {
        guard isCompact, stage != stageTarget,
              let next = CompactStage(rawValue: stage.rawValue + (stage < stageTarget ? 1 : -1)) else { return }
        stage = next
        onMorph?(Motion.stepBusy, compactSizes.size(for: next))
        stageWork = after(Motion.stepGap) { [weak self] in self?.stepStage() }
    }

    private func after(_ seconds: TimeInterval, _ f: @escaping () -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem(block: f)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        return work
    }

    func bind(_ todo: TodoItem) { onStartPicking?(todo) }
    func pickPendingBinding() { onStartPicking?(nil) }

    func jump(_ todo: TodoItem) {
        guard let b = todo.binding, jumpingID == nil else { return }
        jumpingID = todo.id
        ContextRestore.jump(b) { [weak self] result in
            guard let self else { return }
            self.jumpingID = nil
            switch result {
            case .success(let outcome):
                Log.write("Jump result \(outcome)")
                self.showToast(outcome.message)
            case .failure(let err):
                Log.write("Jump failed \(err)")
                self.showToast(err.message)
            }
        }
    }

    func showToast(_ text: String, seconds: Double = 2.5) {
        toastToken += 1
        let token = toastToken
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.toastToken == token else { return }
            self.toast = nil
        }
    }
}

/// Accessibility permission state.
final class PermissionState: ObservableObject {
    @Published var accessibility: Bool = AX.isTrusted
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = AX.isTrusted
            if now != self.accessibility {
                Log.write("Accessibility permission changed -> \(now)")
                self.accessibility = now
            }
        }
    }

    func request() {
        Log.write("Requesting Accessibility permission, currently trusted=\(AX.isTrusted)")
        AX.requestTrust()
        if !AX.isTrusted {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
