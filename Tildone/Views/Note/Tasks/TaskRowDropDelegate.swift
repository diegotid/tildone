//
//  TaskRowDropDelegate.swift
//  Tildone
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct TaskRowDropDelegate: DropDelegate {
    let rowIndex: Int
    let rowHeight: CGFloat
    @Binding var placement: TaskRowDropPlacement?
    let onDrop: (MacTaskDragPayload, Int) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.itemProviders(for: [.json]).count == 1
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        placement = placement(at: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        placement = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.json])
        guard providers.count == 1, let provider = providers.first else {
            placement = nil
            return false
        }

        let destination = destination(for: placement(at: info.location))
        placement = nil
        provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, _ in
            guard let data,
                  let payload = try? JSONDecoder().decode(MacTaskDragPayload.self, from: data) else {
                return
            }
            DispatchQueue.main.async {
                _ = onDrop(payload, destination)
            }
        }
        return true
    }

    private func placement(at location: CGPoint) -> TaskRowDropPlacement {
        let topInset = placement == .before ? TaskReorderFeedback.insertionSpacing : 0
        return location.y - topInset < rowHeight / 2 ? .before : .after
    }

    private func destination(for placement: TaskRowDropPlacement) -> Int {
        placement == .before ? rowIndex : rowIndex + 1
    }
}
