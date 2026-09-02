//
//  TildoneiOSUndoOverlay.swift
//  Tildone
//

import SwiftUI
import UIKit
import TildoneDomain

struct TildoneiOSUndoOverlay: View {
    @ObservedObject var presentation: TildoneiOSUndoPresentation
    @Environment(\.undoManager) private var systemUndoManager
    @StateObject private var invocationTarget = TildoneiOSUndoInvocationTarget()
    let undo: () async throws -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            TildoneiOSShakeUndoResponder(
                isEnabled: presentation.action != nil
            ) {
                presentation.performUndo(using: undo)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            if presentation.isControlVisible, let action = presentation.action {
                Button {
                    presentation.performUndo(using: undo)
                } label: {
                    Label(action.localizedUndoTitle, systemImage: "arrow.uturn.backward")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(.regularMaterial, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.localizedUndoTitle)
                .accessibilityHint("Reverses the latest local change")
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: presentation.isControlVisible)
        .onAppear(perform: synchronizeSystemUndo)
        .onChange(of: presentation.registrationRevision) { _, _ in
            synchronizeSystemUndo()
        }
        .onDisappear {
            systemUndoManager?.removeAllActions(withTarget: invocationTarget)
        }
        .alert("Couldn’t undo this change", isPresented: Binding(
            get: { presentation.errorMessage != nil },
            set: { if !$0 { presentation.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { presentation.errorMessage = nil }
        } message: {
            Text(presentation.errorMessage ?? "")
        }
    }

    private func synchronizeSystemUndo() {
        guard let systemUndoManager else { return }
        systemUndoManager.removeAllActions(withTarget: invocationTarget)
        guard let action = presentation.action else {
            invocationTarget.invoke = nil
            return
        }
        invocationTarget.invoke = {
            presentation.performUndo(using: undo)
        }
        systemUndoManager.registerUndo(withTarget: invocationTarget) { target in
            target.performUndo()
        }
        systemUndoManager.setActionName(action.localizedUndoActionName)
    }
}

struct TildoneiOSUndoMenuButton: View {
    @ObservedObject var presentation: TildoneiOSUndoPresentation
    let undo: () async throws -> Void

    var body: some View {
        Button {
            presentation.performUndo(using: undo)
        } label: {
            Label(
                presentation.action?.localizedUndoTitle ?? String(localized: "Undo"),
                systemImage: "arrow.uturn.backward"
            )
        }
        .disabled(presentation.action == nil)
    }
}

@MainActor
private final class TildoneiOSUndoInvocationTarget: NSObject, ObservableObject {
    var invoke: (() -> Void)?

    func performUndo() {
        invoke?()
    }
}

struct TildoneiOSShakeUndoResponder: UIViewControllerRepresentable {
    let isEnabled: Bool
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(isEnabled: isEnabled, onShake: onShake)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(isEnabled: isEnabled, onShake: onShake)
    }

    @MainActor
    final class Controller: UIViewController {
        private var isUndoEnabled: Bool
        private var isKeyboardVisible = false
        private var onShake: () -> Void
        private var notificationObservers: [NSObjectProtocol] = []

        init(isEnabled: Bool, onShake: @escaping () -> Void) {
            isUndoEnabled = isEnabled
            self.onShake = onShake
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        deinit {
            for observer in notificationObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        override var canBecomeFirstResponder: Bool {
            isUndoEnabled && !isKeyboardVisible
        }

        override func loadView() {
            let responderView = ResponderView()
            responderView.didMoveToWindowHandler = { [weak self] in
                self?.activateIfPossible()
            }
            view = responderView
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            observeApplicationAndKeyboardState()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            activateIfPossible()
        }

        override func viewWillDisappear(_ animated: Bool) {
            if isFirstResponder { resignFirstResponder() }
            super.viewWillDisappear(animated)
        }

        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            guard motion == .motionShake, isUndoEnabled else {
                super.motionEnded(motion, with: event)
                return
            }
            onShake()
        }

        func update(isEnabled: Bool, onShake: @escaping () -> Void) {
            isUndoEnabled = isEnabled
            self.onShake = onShake
            if !isEnabled {
                if isFirstResponder { resignFirstResponder() }
            } else {
                scheduleActivation()
            }
        }

        private func scheduleActivation() {
            DispatchQueue.main.async { [weak self] in
                self?.activateIfPossible()
            }
        }

        private func activateIfPossible() {
            guard canBecomeFirstResponder, viewIfLoaded?.window != nil, !isFirstResponder else {
                return
            }
            becomeFirstResponder()
        }

        private func observeApplicationAndKeyboardState() {
            let center = NotificationCenter.default
            notificationObservers.append(center.addObserver(
                forName: UIResponder.keyboardWillShowNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.isKeyboardVisible = true
            })
            notificationObservers.append(center.addObserver(
                forName: UIResponder.keyboardDidHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.isKeyboardVisible = false
                self?.activateIfPossible()
            })
            notificationObservers.append(center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.activateIfPossible()
            })
        }

        private final class ResponderView: UIView {
            var didMoveToWindowHandler: (() -> Void)?

            override init(frame: CGRect) {
                super.init(frame: frame)
                isUserInteractionEnabled = false
                backgroundColor = .clear
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) { nil }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                if window != nil { didMoveToWindowHandler?() }
            }
        }
    }
}
