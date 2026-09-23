import UIKit

 open  class ViewBoundsObserver {
   public typealias Handler = (
        _ view: UIView,
        _ oldBounds: CGRect,
        _ newBounds: CGRect
    ) -> Void

    private var boundsObservation: NSKeyValueObservation?
    private var frameObservation: NSKeyValueObservation?
    private var lastReportedBounds: CGRect

   public init(
        view: UIView,
        handler: @escaping Handler
    ) {
        lastReportedBounds = view.bounds

        // 直接修改 bounds 的场景（例如附件测量完成后更新自身尺寸）。
        boundsObservation = view.observe(
            \.bounds,
            options: [.old, .new]
        ) { [weak self, weak view] _, change in
            guard
                let self,
                let view,
                let oldBounds = change.oldValue,
                let newBounds = change.newValue
            else {
                return
            }
            self.report(view: view,
                        oldBounds: oldBounds,
                        newBounds: newBounds,
                        handler: handler)
        }

        // 手工设置 `view.frame` 的场景。UIKit 的 setFrame: 不承诺同时对
        // UIView.bounds 发 KVO 通知，因此仅监听 bounds 会漏掉这条路径。
        frameObservation = view.observe(
            \.frame,
            options: [.old, .new]
        ) { [weak self, weak view] _, change in
            guard
                let self,
                let view,
                let oldFrame = change.oldValue,
                let newFrame = change.newValue
            else {
                return
            }

            let origin = view.bounds.origin
            self.report(view: view,
                        oldBounds: CGRect(origin: origin, size: oldFrame.size),
                        newBounds: CGRect(origin: origin, size: newFrame.size),
                        handler: handler)
        }
    }

    private func report(view: UIView,
                        oldBounds: CGRect,
                        newBounds: CGRect,
                        handler: Handler) {
        guard oldBounds.size != newBounds.size, newBounds.size != lastReportedBounds.size else { return }
        lastReportedBounds = newBounds
        handler(view, oldBounds, newBounds)
    }

    func invalidate() {
        boundsObservation?.invalidate()
        frameObservation?.invalidate()
        boundsObservation = nil
        frameObservation = nil
    }

    deinit {
        invalidate()
    }
}
