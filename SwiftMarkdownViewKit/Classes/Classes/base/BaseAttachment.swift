//
//  BaseAttachment.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/11.
//

import UIKit
import Markdown

public enum StreamState {
    case none
    case streaming
    case paused
    case finished
}

public struct ViewOption {
    
    ///定义一个属性为空的时候默认值
    public static let  defaultValue: CGFloat = 200
    ///内部自动根据MarkdownView 最大文本宽度减去边距
    public var minWidth: CGFloat? = nil
    ///内部自动根据MarkdownView 最大文本宽度减去边距
    public var maxWidth: CGFloat? = nil
    
    public var estimedSize: CGSize? = nil
    
    public var placeholderImage: UIImage? = nil
    
    public var extraInfo: Any? = nil
    
    public var textMatch: TextMatch? = nil
}

class BaseAttachment: NSTextAttachment {
    public var streamState: StreamState = .none
    public lazy var view:  ViewLoadable = {
        let view = viewBlock()
        return view
    }()
    public var onLayoutChange: ((BaseAttachment) -> Void)?
    public var range: NSRange?
    let viewBlock: () -> ViewLoadable
    public var markupCtx: MarkupContext<Markup>
    
    public required init(markup: MarkupContext<Markup>,viewBlock: @escaping () -> ViewLoadable) {
        self.markupCtx = markup
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
            confiureViewOptions(view: view)
            let maxWidth = markDownView()?.maxTextWidth ?? UIScreen.main.bounds.width
            view.onContentSizeChanged = { [weak self] size in
                guard let self = self else { return }
                var newBounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                newBounds = self.adjustAttacmentBounds(newBounds)
                newBounds.size.width = min(newBounds.width, maxWidth)
                if self.bounds != newBounds {
                    self.bounds = newBounds
                    onLayoutChange(self)
                }
            }
            let estimeSize = estimatedSize(view)
            bounds = CGRect(origin: .zero, size: estimeSize)
            let contentInset = view.attachmentContentInset()
            view.frame = adjustFrame(CGRect(origin: frame.origin, size: estimeSize))
            if animated {
                view.onStreamingFinished = completion
                startStreaming(view,animation: true)
            } else {
                // 非动画：一次性显示完整表格。
                startStreaming(view,animation: false)
                onLayoutChange(self)
                completion()
            }
        }
   
    public func removeView() {
        guard streamState != .none else { return }
        view.removeFromSuperview()
        onLayoutChange = nil
    }
    
    public func updateViewFrame(_ frame: CGRect, in hostView: UIView) {
        let contentInset = view.attachmentContentInset()
        let w = bounds.size.width - contentInset.left - contentInset.right
        let h = bounds.size.height - contentInset.top - contentInset.bottom
        view.frame = adjustFrame(CGRect(origin: frame.origin, size: CGSize(width: w, height: h)))

    }
    
    private func adjustFrame(_ frame: CGRect) -> CGRect {
        let contentInset = view.attachmentContentInset()
        var adjustedFrame = frame
        adjustedFrame.origin.x += contentInset.left
        adjustedFrame.origin.y += contentInset.top
        return adjustedFrame
    }
    
    private func adjustAttacmentBounds(_ bounds: CGRect) -> CGRect {
        let contentInset = view.attachmentContentInset()
        var adjustedBounds = bounds
        adjustedBounds.size.width += contentInset.left + contentInset.right
        adjustedBounds.size.height += contentInset.top + contentInset.bottom
        return adjustedBounds
    }
    private func textView() -> UITextView? {
       return markDownView()?.textView
    }
    private func markDownView() -> MarkdownView? {
        guard let MarkdownView = view.superview?.superview as? MarkdownView else {
            return nil
        }
        return MarkdownView
    }
    private func confiureViewOptions(view: ViewLoadable) {
        
        guard let markdownView = markDownView() else {return}
        
        let inset = view.attachmentContentInset()
        
        let textViewInset = markdownView.textView.textContainerInset
        
        let w = textViewInset.left + textViewInset.right + markdownView.textView.textContainer.lineFragmentPadding * 2 + inset.left + inset.right
        if view.viewOptions.maxWidth == nil {
            view.viewOptions.maxWidth = markdownView.maxTextWidth - w
        }
        if view.viewOptions.minWidth == nil {
            view.viewOptions.minWidth = markdownView.minTextWidth - w
        }
        if view.viewOptions.estimedSize == nil {
            view.viewOptions.estimedSize = CGSize(width: view.viewOptions.maxWidth ?? ViewOption.defaultValue, height: 100)
        }
        view.updateViewOptions(view.viewOptions)
        if let view = view as? GridTableView,let markup = markupCtx.markup as? Table {
            
            let ctx = MarkupRenderContext(view: view, markdownView: markdownView, markup: markup, visitor: markupCtx.visitor, match: markupCtx.match)
            markdownView.delegate?.configureGridTableView(ctx)
            
        }else if let view = view as? ImageView,let markup = markupCtx.markup as? Image {
            
            let ctx = MarkupRenderContext(view: view, markdownView: markdownView, markup: markup, visitor: markupCtx.visitor, match: markupCtx.match)
            markdownView.delegate?.configureImageView(ctx)
            
        }else if let view = view as? CodeBlockView,let markup = markupCtx.markup as? CodeBlock  {
            
            let ctx = MarkupRenderContext(view: view, markdownView: markdownView, markup: markup, visitor: markupCtx.visitor, match: markupCtx.match)
            markdownView.delegate?.configureCodeBlockView(ctx)
            
        }else if let view = view as? MarkdownWebBlockView,let markup = markupCtx.markup as? CodeBlock  {
            
            let ctx = MarkupRenderContext(view: view, markdownView: markdownView, markup: markup, visitor: markupCtx.visitor, match: markupCtx.match)
            markdownView.delegate?.configureCodeWebView(ctx)
            
        }else if let view = view as? LatexWebBlockView,let markup = markupCtx.markup as? Paragraph  {
            
            let ctx = MarkupRenderContext(view: view, markdownView: markdownView, markup: markup, visitor: markupCtx.visitor, match: markupCtx.match)
            markdownView.delegate?.configureLatexWebView(ctx)
            
        }else if let view = view as? HTMLWebBlockView,let markup = markupCtx.markup as? HTMLBlock  {
            
            let ctx = MarkupRenderContext(view: view, markdownView: markdownView, markup: markup, visitor: markupCtx.visitor, match: markupCtx.match)
            markdownView.delegate?.configureHTMLWebView(ctx)
            
        }else {
            let context: MarkupRenderTuple = (
                view: view,
                markdownView: markdownView,
                markup: markupCtx.markup,
                visitor: markupCtx.visitor,
                match: markupCtx.match
            )
            markdownView.delegate?.configureCustomView(context)
        }
    }
}
extension BaseAttachment {///类型擦除
    public func startStreaming<V: ViewLoadable>(_ view: V,animation: Bool) {
        guard let typed = markupCtx.markup as? V.MarkupType else { return }
        let ctx = MarkupContext(markup: typed, visitor: markupCtx.visitor,match: markupCtx.match)
        view.startStreaming(data: ctx, animation: animation)
    }
    
    public func estimatedSize<V: ViewLoadable>(_ view: V)-> CGSize {
        guard let typed = markupCtx.markup as? V.MarkupType else { return .zero}
        let ctx = MarkupContext(markup: typed, visitor: markupCtx.visitor,match: markupCtx.match)
    
       return view.estimatedSize(for: ctx)
    }
    public func updataData<V: ViewLoadable>(_ view: V) {
        guard let typed = markupCtx.markup as? V.MarkupType else { return}
        let ctx = MarkupContext(markup: typed, visitor: markupCtx.visitor,match: markupCtx.match)
        if streamState == .streaming {
            streamState = .finished
        }
       return view.updateData(data: ctx)
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
