import AppKit
import Combine

/// What the window's layer mask is cut from (see FirstMouseHostingView.setMask): the plate's current rect (root view coordinates, spanning the ear's column; nil before the first layout)
/// and the ear: how far it is out, and whether it is on the right side of the panel (docked at the left edge) instead of the left.
struct MaskGeometry: Equatable {
    var plate: CGRect?
    var ear: CGFloat = 0.5
    var earRight = false
}

/// The bridge between the UI and the AppKit layer: binding, jumping, toasts, collapse / expand.
final class AppCoordinator: ObservableObject {
    @Published var jumpingID: UUID?
    @Published var toast: String?
    @Published var isPicking = false
    @Published var alwaysOnTop = true
    /// A docked panel slides off the screen when the mouse leaves (see EdgeDock.autoHide); off, it stays out at the edge. Mirrors the dock's setting for the menus.
    @Published var dockAutoHide = true
    /// Collapsed (a glass slab: a row of balls and the most urgent to-do).
    @Published var isCompact = false {
        willSet {
            // Grow / shrink the window before the state changes: SwiftUI lays out once with the new window size and the old state (without animation),
            // then the state changes and animates. Otherwise the root view's size change joins the animation as a geometry animation about the centre and drags the plate off.
            if newValue != isCompact { onCompactChanged?(newValue) }
        }
        didSet { if isCompact { selectedID = nil } }
    }
    /// The to-do opened in the panel (title and notes editable); cleared on collapse.
    @Published var selectedID: UUID?
    /// Whether the composer at the top of the panel is showing: hidden by default, + brings it up.
    @Published var adding = false
    /// The size of the window's content area (reported by FloatingPanel): the expanded panel's plate fills it.
    @Published var panelSize = CGSize(width: 360, height: 480)
    /// The screen edge the panel is docked at (see EdgeDock): the plate runs on past the window's edge on that side, so its corners there are square against the edge;
    /// docked at the left edge the ear moves to the right side of the panel.
    @Published var dockSide: EdgeDock.Side? { didSet { mask.earRight = dockSide == .left } }
    /// Docked and slid off the screen, only the strip at the edge showing (see EdgeDock.isTucked): the strip carries the first timed to-do's countdown bar.
    @Published var dockTucked = false
    /// The binding and time "chosen but not yet created" in the composer.
    @Published var pendingBinding: ContextBinding?
    @Published var pendingDue: DueSpec?

    /// Pick: nil means picking for the to-do about to be created in the composer.
    var onStartPicking: ((TodoItem?) -> Void)?
    var onAlwaysOnTopChanged: ((Bool) -> Void)?
    var onDockAutoHideChanged: ((Bool) -> Void)?
    var onCompactChanged: ((Bool) -> Void)?
    /// The plate's current rect (root view coordinates) and how far the ear is out: RootView reports them every frame (mid-animation values) and the window's layer mask follows.
    /// Keeps the latest value because the root view is first evaluated before the window hooks up onMaskChange (see AppDelegate).
    var mask = MaskGeometry() { didSet { if mask != oldValue { onMaskChange?(mask) } } }
    var onMaskChange: ((MaskGeometry) -> Void)?
    var onQuit: (() -> Void)?

    private var toastToken = 0

    /// Hide at the screen edge on / off, from the ⋯ menu or the menu bar menu.
    func setDockAutoHide(_ on: Bool) {
        dockAutoHide = on
        onDockAutoHideChanged?(on)
    }

    /// Launch straight into the collapsed state (no collapse animation: the window has not hooked up onCompactChanged yet).
    func restoreCompact() { isCompact = true }

    /// Expand the panel to create: put the composer into the (still off-window) panel first and expand on the next turn, so the expand animation does not stall at the start.
    func expandToAdd() {
        adding = true
        DispatchQueue.main.async { self.isCompact = false }
    }

    /// Expand the panel to a to-do's details.
    func expand(showing id: UUID) {
        selectedID = id
        DispatchQueue.main.async { self.isCompact = false }
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
