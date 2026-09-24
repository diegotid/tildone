//
//  TaskReorderHandle.swift
//  Tildone
//

import AppKit
import SwiftUI

struct TaskReorderHandle: View {
    let payload: MacTaskDragPayload
    let taskText: String
    let isCompleted: Bool
    let fontSize: Double
    let isDark: Bool
    let size: CGFloat

    var body: some View {
        NativeTaskReorderHandle(
            payload: payload,
            taskText: taskText,
            isCompleted: isCompleted,
            fontSize: fontSize,
            isDark: isDark
        )
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(
                        (isDark ? Color(.primaryFontWhite) : Color(.primaryFontColor)).opacity(0.45)
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .help("Drag to reorder")
    }
}

private struct NativeTaskReorderHandle: NSViewRepresentable {
    let payload: MacTaskDragPayload
    let taskText: String
    let isCompleted: Bool
    let fontSize: Double
    let isDark: Bool

    func makeNSView(context: Context) -> TaskReorderHandleNSView {
        let view = TaskReorderHandleNSView()
        view.payload = payload
        view.preview = TaskReorderPreview(
            taskText: taskText,
            isCompleted: isCompleted,
            fontSize: fontSize,
            isDark: isDark
        )
        return view
    }

    func updateNSView(_ view: TaskReorderHandleNSView, context: Context) {
        view.payload = payload
        view.preview = TaskReorderPreview(
            taskText: taskText,
            isCompleted: isCompleted,
            fontSize: fontSize,
            isDark: isDark
        )
    }
}

private final class TaskReorderHandleNSView: NSView, NSDraggingSource {
    var payload: MacTaskDragPayload?
    var preview: TaskReorderPreview?
    private var isDragging = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? { String(localized: "Reorder task") }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let payload,
              let data = try? JSONEncoder().encode(payload) else { return }
        let item = NSPasteboardItem()
        item.setData(data, forType: NSPasteboard.PasteboardType(MacTaskDragPayload.contentType.identifier))
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        let renderer = preview.map { ImageRenderer(content: $0) }
        renderer?.scale = window?.backingScaleFactor ?? 2
        let image = renderer?.nsImage
            ?? NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
            ?? NSImage(size: bounds.size)
        draggingItem.setDraggingFrame(
            NSRect(origin: bounds.origin, size: image.size),
            contents: image
        )
        isDragging = true
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDragging = false
    }
}
