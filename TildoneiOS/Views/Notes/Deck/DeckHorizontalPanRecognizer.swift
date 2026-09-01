import SwiftUI
import UIKit

struct DeckHorizontalPanRecognizer: UIViewRepresentable {
    let canMove: (DeckNavigationDirection) -> Bool
    let changed: (CGFloat, CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void
    let cancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(canMove: canMove, changed: changed, ended: ended, cancelled: cancelled)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { context.coordinator.attach(to: view) }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.canMove = canMove
        context.coordinator.changed = changed
        context.coordinator.ended = ended
        context.coordinator.cancelled = cancelled
        context.coordinator.attach(to: view)
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canMove: (DeckNavigationDirection) -> Bool
        var changed: (CGFloat, CGFloat) -> Void
        var ended: (CGFloat, CGFloat) -> Void
        var cancelled: () -> Void
        private let panGesture: UIPanGestureRecognizer
        private weak var trackingView: UIView?
        private weak var scrollView: UIScrollView?

        init(
            canMove: @escaping (DeckNavigationDirection) -> Bool,
            changed: @escaping (CGFloat, CGFloat) -> Void,
            ended: @escaping (CGFloat, CGFloat) -> Void,
            cancelled: @escaping () -> Void
        ) {
            self.canMove = canMove
            self.changed = changed
            self.ended = ended
            self.cancelled = cancelled
            panGesture = UIPanGestureRecognizer()
            super.init()
            panGesture.addTarget(self, action: #selector(handlePan))
            panGesture.delegate = self
            panGesture.cancelsTouchesInView = false
        }

        func attach(to view: UIView) {
            trackingView = view
            guard scrollView == nil, let enclosingScrollView = enclosingScrollView(from: view) else { return }
            enclosingScrollView.addGestureRecognizer(panGesture)
            enclosingScrollView.panGestureRecognizer.require(toFail: panGesture)
            scrollView = enclosingScrollView
        }

        func detach() {
            panGesture.view?.removeGestureRecognizer(panGesture)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let velocity = panGesture.velocity(in: scrollView)
            guard abs(velocity.x) > abs(velocity.y) * 1.35 else { return false }
            return canMove(velocity.x < 0 ? .next : .previous)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let trackingView, let scrollView else { return false }
            let carouselFrame = trackingView.convert(trackingView.bounds, to: scrollView)
            return carouselFrame.contains(touch.location(in: scrollView))
        }

        @objc private func handlePan() {
            let translation = panGesture.translation(in: scrollView)
            let velocity = panGesture.velocity(in: scrollView)
            switch panGesture.state {
            case .began, .changed:
                changed(translation.x, velocity.x)
            case .ended:
                ended(translation.x, velocity.x)
            case .cancelled, .failed:
                cancelled()
            default:
                break
            }
        }
    }
}

func enclosingScrollView(from view: UIView) -> UIScrollView? {
    var candidate = view.superview
    while let current = candidate {
        if let scrollView = current as? UIScrollView { return scrollView }
        candidate = current.superview
    }
    var responder: UIResponder? = view.next
    while let current = responder {
        if let scrollView = current as? UIScrollView { return scrollView }
        responder = current.next
    }
    return nil
}
