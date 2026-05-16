import AppKit

final class HotkeyManager {
    private let onDoubleTap: () -> Void
    private var monitor: Any?
    private var lastCmdReleaseTime: Date?
    private var cmdHeldAlone = false
    private let doubleTapWindow: TimeInterval = 0.3

    init(onDoubleTap: @escaping () -> Void) {
        self.onDoubleTap = onDoubleTap
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            // Run state machine on main to avoid races on lastCmdReleaseTime / cmdHeldAlone.
            if Thread.isMainThread {
                self?.handle(event)
            } else {
                DispatchQueue.main.async { self?.handle(event) }
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmdDown = flags.contains(.command)
        let otherMods = flags.subtracting(.command).intersection([.shift, .control, .option])

        if !otherMods.isEmpty {
            cmdHeldAlone = false
            lastCmdReleaseTime = nil
            return
        }

        if cmdDown {
            cmdHeldAlone = true
        } else {
            // cmd just released alone
            if cmdHeldAlone {
                let now = Date()
                if let last = lastCmdReleaseTime, now.timeIntervalSince(last) < doubleTapWindow {
                    lastCmdReleaseTime = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.onDoubleTap()
                    }
                } else {
                    lastCmdReleaseTime = now
                }
                cmdHeldAlone = false
            } else {
                lastCmdReleaseTime = nil
            }
        }
    }
}
