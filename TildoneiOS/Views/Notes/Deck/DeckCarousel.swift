import SwiftUI
import TildoneDomain
import UIKit

struct DeckCarousel: View {
    let notes: [Note]
    let summaries: [NoteID: NoteTaskSummary]
    let taskPreviews: [NoteID: [NoteTaskPreview]]
    let cardHeight: CGFloat
    let contentScale: CGFloat
    let open: (Note) -> Void
    let rename: (Note) -> Void
    let delete: (Note) -> Void
    @State private var currentNoteID: NoteID?
    @State private var transitionProgress: CGFloat = 0
    @State private var isCompletingSwipe = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ForEach(visibleCards) { item in
                    let isCurrentCard = item.relativePosition == 0
                    let effectivePosition = Double(item.relativePosition) - Double(transitionProgress)
                    let transform = cardTransform(at: effectivePosition)
                    NoteCard(
                        note: item.note,
                        summary: summaries[item.note.id],
                        tasks: taskPreviews[item.note.id] ?? [],
                        style: .deck,
                        height: cardHeight,
                        contentScale: contentScale,
                        rename: { rename(item.note) },
                        delete: { delete(item.note) }
                    )
                    .frame(width: NoteCardLayoutMetrics.deckWidth(in: proxy.size.width))
                    .scaleEffect(transform.scale, anchor: .bottom)
                    .offset(x: transform.x, y: transform.y)
                    .rotationEffect(.degrees(transform.rotation), anchor: .bottom)
                    .opacity(transform.opacity)
                    .zIndex(100 - abs(effectivePosition))
                    .allowsHitTesting(isCurrentCard)
                    .onTapGesture {
                        if isCurrentCard { open(item.note) }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .background {
                DeckHorizontalPanRecognizer(
                    canMove: canMove,
                    changed: { translation, _ in handlePanChanged(translation, in: proxy.size) },
                    ended: { translation, velocity in
                        handlePanEnded(translation, velocity: velocity, in: proxy.size)
                    },
                    cancelled: cancelPan
                )
            }
        }
        .frame(height: cardHeight + 52)
        .onAppear(perform: reconcileCurrentNote)
        .onChange(of: notes.map(\.id)) { _, _ in reconcileCurrentNote() }
    }

    private func handlePanChanged(_ translation: CGFloat, in size: CGSize) {
        guard !isCompletingSwipe else { return }
        transitionProgress = progress(for: translation, in: size.width)
    }

    private func handlePanEnded(_ translation: CGFloat, velocity: CGFloat, in size: CGSize) {
        guard !isCompletingSwipe else { return }
        let projectedProgress = progress(for: translation + velocity * 0.18, in: size.width)
        if canMoveNext,
           transitionProgress > 0.48 || projectedProgress > 0.72 {
            completeSwipe(.next, velocity: velocity, in: size)
        } else if canMovePrevious,
                  transitionProgress < -0.48 || projectedProgress < -0.72 {
            completeSwipe(.previous, velocity: velocity, in: size)
        } else {
            cancelPan()
        }
    }

    private func cancelPan() {
        withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
            transitionProgress = 0
        }
    }

    private func completeSwipe(
        _ direction: DeckNavigationDirection,
        velocity: CGFloat,
        in size: CGSize
    ) {
        isCompletingSwipe = true
        let projectedVelocity = min(4, abs(velocity) / max(size.width, 1))
        let destination: CGFloat = direction == .next ? 1 : -1

        withAnimation(
            .interpolatingSpring(stiffness: 180, damping: 22, initialVelocity: projectedVelocity),
            completionCriteria: .logicallyComplete
        ) {
            transitionProgress = destination
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                currentNoteID = notes[destinationIndex(for: direction)].id
                transitionProgress = 0
                isCompletingSwipe = false
            }
        }
    }

    private var visibleCards: [DeckCardItem] {
        guard notes.indices.contains(currentIndex) else { return [] }
        let lowerBound = max(notes.startIndex, currentIndex - 3)
        let upperBound = min(notes.index(before: notes.endIndex), currentIndex + 3)
        return (lowerBound...upperBound).map { index in
            DeckCardItem(note: notes[index], relativePosition: index - currentIndex)
        }
    }

    private var currentIndex: Int {
        guard let currentNoteID,
              let index = notes.firstIndex(where: { $0.id == currentNoteID }) else { return 0 }
        return index
    }

    private var canMovePrevious: Bool { currentIndex > notes.startIndex }
    private var canMoveNext: Bool { currentIndex + 1 < notes.endIndex }

    private func canMove(_ direction: DeckNavigationDirection) -> Bool {
        switch direction {
        case .previous: canMovePrevious
        case .next: canMoveNext
        }
    }

    private func destinationIndex(for direction: DeckNavigationDirection) -> Int {
        switch direction {
        case .previous: currentIndex - 1
        case .next: currentIndex + 1
        }
    }

    private func reconcileCurrentNote() {
        let activeIDs = Set(notes.map(\.id))
        if currentNoteID.map(activeIDs.contains) != true {
            currentNoteID = notes.first?.id
        }
    }

    private func progress(for horizontalTranslation: CGFloat, in width: CGFloat) -> CGFloat {
        var progress = -horizontalTranslation / max(width * 0.36, 1)
        if progress > 0, !canMoveNext { progress *= 0.18 }
        if progress < 0, !canMovePrevious { progress *= 0.18 }
        return min(1.15, max(-1.15, progress))
    }

    private func cardTransform(at position: Double) -> DeckCardTransform {
        let direction = position.sign == .minus ? -1.0 : 1.0
        let magnitude = min(abs(position), 3)
        let horizontal = 44 * magnitude - 4 * magnitude * max(0, magnitude - 1)
        return DeckCardTransform(
            x: CGFloat(direction * horizontal),
            y: CGFloat(7 * magnitude + 1.5 * magnitude * magnitude),
            scale: CGFloat(1 - 0.038 * magnitude),
            rotation: direction * (3.2 * magnitude + 0.45 * magnitude * magnitude),
            opacity: max(0.46, 1 - 0.17 * magnitude)
        )
    }
}
