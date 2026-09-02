import UIKit

final class ViewBoundsObserver {
    typealias Handler = (
        _ view: UIView,
        _ oldBounds: CGRect,
        _ newBounds: CGRect
    ) -> Void

    private var observation: NSKeyValueObservation?

    init(
        view: UIView,
        handler: @escaping Handler
    ) {
        observation = view.observe(
            \.bounds,
            options: [.old, .new]
        ) { [weak self] view, change in
            guard
                self != nil,
                let oldBounds = change.oldValue,
                let newBounds = change.newValue,
                oldBounds != newBounds
            else {
                return
            }

            handler(view, oldBounds, newBounds)
        }
    }

    func invalidate() {
        observation?.invalidate()
        observation = nil
    }

    deinit {
        invalidate()
    }
}
