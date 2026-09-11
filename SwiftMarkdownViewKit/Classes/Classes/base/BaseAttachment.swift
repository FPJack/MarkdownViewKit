//
//  BaseAttachment.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/11.
//

import UIKit
public enum StreamState {
    case none
    case streaming
    case paused
    case finished
}

struct AttrKey {
    static let markup_key = NSAttributedString.Key("markup_id")
}


public struct ViewOption {

    public var minWidth: CGFloat = 100
    
    public var maxWidth: CGFloat = 200
    
    public var estimedSize: CGSize = CGSize(width: 100, height: 100)
    
    public var placeholderImage: UIImage? = nil
    
    public var extraInfo: Any? = nil
    
    public var textMatch: TextMatch? = nil
}

class BaseAttachment: NSTextAttachment {
    public var streamState: StreamState = .none
    public var textMatch: TextMatch = TextMatch()
    public lazy var view:  ViewLoadable = viewBlock()
    public var onLayoutChange: ((BaseAttachment) -> Void)?
    public var range: NSRange?
    
    let viewBlock: () -> ViewLoadable


    public required init(viewBlock: @escaping () -> ViewLoadable) {
        self.viewBlock = viewBlock
        super.init(data: nil, ofType: nil)
        self.bounds = .zero
        self.image = randomColorImage(size: CGSize(width: 100, height: 100))
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func beginStreaming(
        in hostView: UIView,
        frame: CGRect,
        animated: Bool,
        onLayoutChange: @escaping (BaseAttachment) -> Void,
        completion: @escaping () -> Void) {
            hostView.addSubview(view)
            view.onContentSizeChanged = { [weak self] size in
                guard let self = self else { return }
                var newBounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                newBounds = self.adjustAttacmentBounds(newBounds)
                if self.bounds != newBounds {
                    self.bounds = newBounds
                    onLayoutChange(self)
                }
            }
            let estimeSize = view.estimatedSize(for: textMatch )
            bounds = CGRect(origin: .zero, size: estimeSize)
            let contentInset = view.attachmentContentInset()
            view.frame = adjustFrame(CGRect(origin: frame.origin, size: estimeSize))
            if animated {
                view.onStreamingFinished = completion
                view.startStreaming(data: textMatch, animation: true)
            } else {
                // 非动画：一次性显示完整表格。
                view.startStreaming(data: textMatch, animation: false)
                onLayoutChange(self)
                completion()
            }
        }
    
    public func removeView() {
        view.removeFromSuperview()
        onLayoutChange = nil
    }
    
    public func updateViewFrame(_ frame: CGRect, in hostView: UIView) {
        let contentInset = view.attachmentContentInset()
        let w = bounds.size.width - contentInset.left - contentInset.right
        let h = bounds.size.height - contentInset.top - contentInset.bottom
        view.frame = adjustFrame(CGRect(origin: frame.origin, size: CGSize(width: w, height: h)))
        print("updateViewFrame: \(bounds.width)")

    }
    
    private func adjustFrame(_ frame: CGRect) -> CGRect {
        
        let contentInset = view.attachmentContentInset()
        var adjustedFrame = frame
        adjustedFrame.origin.x += contentInset.left
        adjustedFrame.origin.y += contentInset.top
        print("adjustFrame: \(adjustedFrame.origin.x)")
        return adjustedFrame
    }
    
    private func adjustAttacmentBounds(_ bounds: CGRect) -> CGRect {
        let contentInset = view.attachmentContentInset()
        var adjustedBounds = bounds
        adjustedBounds.size.width += contentInset.left + contentInset.right
        adjustedBounds.size.height += contentInset.top + contentInset.bottom
        return adjustedBounds
    }
    

}
private func randomColor() -> UIColor {
        return .clear
    let red = CGFloat.random(in: 0...1)
    let green = CGFloat.random(in: 0...1)
    let blue = CGFloat.random(in: 0...1)
    return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
}
private func randomColorImage(size: CGSize) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        let color = randomColor()
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}


public class PlaceholderAttachment: NSTextAttachment {
    
    let viewBlock: () -> ViewLoadable
    
    init(viewBlock: @escaping () -> ViewLoadable) {
        self.viewBlock = viewBlock
        super.init(data: nil, ofType: nil)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
