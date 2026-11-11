import AppKit
import SwiftUI

struct WindowDragHandle: NSViewRepresentable {
    var isEnabled: Bool

    func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        view.isEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {
        nsView.isEnabled = isEnabled
    }
}

final class DragHandleView: NSView {
    private var mouseDownLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?

    var isEnabled = true {
        didSet {
            guard oldValue != isEnabled else {
                return
            }
            if !isEnabled {
                finishDragging()
            }
            window?.invalidateCursorRects(for: self)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        isEnabled
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else {
            return
        }
        mouseDownLocation = NSEvent.mouseLocation
        initialWindowOrigin = window.frame.origin
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled,
              let window,
              let mouseDownLocation,
              let initialWindowOrigin else {
            return
        }
        let currentLocation = NSEvent.mouseLocation
        window.setFrameOrigin(
            NSPoint(
                x: initialWindowOrigin.x + currentLocation.x - mouseDownLocation.x,
                y: initialWindowOrigin.y + currentLocation.y - mouseDownLocation.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        finishDragging()
    }

    private func finishDragging() {
        guard mouseDownLocation != nil else {
            return
        }
        mouseDownLocation = nil
        initialWindowOrigin = nil
        NSCursor.pop()
        if let window {
            let autosaveName = window.frameAutosaveName
            guard !autosaveName.isEmpty else {
                return
            }
            window.saveFrame(usingName: autosaveName)
        }
    }
}
