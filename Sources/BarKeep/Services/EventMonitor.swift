import AppKit

/// Thin wrapper around local/global `NSEvent` monitors.
final class EventMonitor {
    private var local: Any?
    private var global: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    func start() {
        guard local == nil, global == nil else { return }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handler(event)
            return event
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handler(event)
        }
    }

    func stop() {
        if let local {
            NSEvent.removeMonitor(local)
            self.local = nil
        }
        if let global {
            NSEvent.removeMonitor(global)
            self.global = nil
        }
    }

    deinit {
        stop()
    }
}
