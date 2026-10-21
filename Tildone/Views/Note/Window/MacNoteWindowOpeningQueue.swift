import Foundation
import TildoneDomain

/// Show the first requested note immediately, then let AppKit process input
/// and drawing between the remaining window constructions.
@MainActor
final class MacNoteWindowOpeningQueue {
    private var pending: ArraySlice<NoteID> = []
    private var open: ((NoteID) -> Void)?
    private var onCompletion: (() -> Void)?
    private var scheduled: DispatchWorkItem?
    private var generation: UInt64 = 0

    func replace(
        with noteIDs: [NoteID],
        onCompletion: @escaping () -> Void = {},
        open: @escaping (NoteID) -> Void
    ) {
        cancel()
        guard !noteIDs.isEmpty else { return }
        pending = noteIDs[...]
        self.open = open
        self.onCompletion = onCompletion
        openNext(generation: generation)
    }

    func cancel() {
        generation &+= 1
        scheduled?.cancel()
        scheduled = nil
        pending = []
        open = nil
        onCompletion = nil
    }

    private func openNext(generation expected: UInt64) {
        guard generation == expected, let noteID = pending.popFirst() else { return }
        open?(noteID)
        // Opening a note can trigger reconciliation again. Never continue a
        // superseded batch, including after a filter change or Desktop close.
        guard generation == expected else { return }
        guard !pending.isEmpty else {
            let completion = onCompletion
            open = nil
            onCompletion = nil
            // Space membership and native window layout may settle after
            // orderBack returns. Finish layout on the following UI turn.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.generation == expected else { return }
                self.scheduled = nil
                completion?()
            }
            scheduled = work
            DispatchQueue.main.async(execute: work)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.openNext(generation: expected)
        }
        scheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1), execute: work)
    }
}
