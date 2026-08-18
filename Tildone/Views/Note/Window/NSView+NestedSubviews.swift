//
//  NSView+NestedSubviews.swift
//  Tildone
//

import AppKit

extension NSView {
    class func getNestedSubviews<T: NSView>(view: NSView) -> [T] {
        view.subviews.flatMap { subview -> [T] in
            var result = getNestedSubviews(view: subview) as [T]
            if let view = subview as? T {
                result.append(view)
            }
            return result
        }
    }

    func getNestedSubviews<T: NSView>() -> [T] {
        NSView.getNestedSubviews(view: self) as [T]
    }
}
