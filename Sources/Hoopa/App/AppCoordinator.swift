import AppKit
import Combine

/// The bridge between the UI and the AppKit layer: binding, jumping, toasts, collapse / expand.
final class AppCoordinator: ObservableObject {
    @Published var jumpingID: UUID?
    @Published var toast: String?
    @Published var isPicking = false
    @Published var alwaysOnTop = true
    /// Collapse into the pill (only the most urgent to-do showing).
    @Published var isCompact = false { didSet { if oldValue != isCompact { onCompactChanged?(isCompact) } } }
    /// The binding and time "chosen but not yet created" in the composer.
    @Published var pendingBinding: ContextBinding?
    @Published var pendingDue: Due?

    /// Pick: nil means picking for the to-do about to be created in the composer.
    var onStartPicking: ((TodoItem?) -> Void)?
    var onAlwaysOnTopChanged: ((Bool) -> Void)?
    var onCompactChanged: ((Bool) -> Void)?
    var onQuit: (() -> Void)?

    private var toastToken = 0

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
