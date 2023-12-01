//
//  WindowAccessor.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension NSView {

    class func getNestedSubviews<T: NSView>(view: NSView) -> [T] {
        return view.subviews.flatMap { subView -> [T] in
            var result = getNestedSubviews(view: subView) as [T]
            if let view = subView as? T {
                result.append(view)
            }
            return result
        }
    }

    func getNestedSubviews<T: NSView>() -> [T] {
        return NSView.getNestedSubviews(view: self) as [T]
    }
}
