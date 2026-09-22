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

    // MARK: - 宽度
    //
    // `minWidth` / `maxWidth` / `estimedSize` 有两种来源：
    //   1. **库内部自动推导**：由 MarkdownView 的 `maxTextWidth` 减去各层边距得到；
    //   2. **业务方显式设置**：通过 delegate 回调或直接赋值指定。
    //
    // 容器宽度变化（横竖屏切换、分屏、窗口缩放）时，只有第 1 类需要重新推导，
    // 第 2 类必须原样保留——否则业务方设的固定宽度会在旋转后被悄悄冲掉。
    //
    // 这里用「外部赋值即视为显式设置」的方式自动区分：
    // 公开的 setter 会把 auto 标记清掉，库内部则走 `setAutoResolved*` 方法。

    private var _minWidth: CGFloat? = nil
    private var _maxWidth: CGFloat? = nil
    private var _estimedSize: CGSize? = nil

    /// 内部自动根据 MarkdownView 最大文本宽度减去边距；也可由外部显式指定。
    public var minWidth: CGFloat? {
        get { _minWidth }
        set { _minWidth = newValue; isMinWidthAutoResolved = false }
    }

    /// 内部自动根据 MarkdownView 最大文本宽度减去边距；也可由外部显式指定。
    public var maxWidth: CGFloat? {
        get { _maxWidth }
        set { _maxWidth = newValue; isMaxWidthAutoResolved = false }
    }

    public var estimedSize: CGSize? {
        get { _estimedSize }
        set { _estimedSize = newValue; isEstimedSizeAutoResolved = false }
    }

    /// 当前 `minWidth` 是否为库内部自动推导（可在容器宽度变化时刷新）。
    public private(set) var isMinWidthAutoResolved: Bool = false
    /// 当前 `maxWidth` 是否为库内部自动推导（可在容器宽度变化时刷新）。
    public private(set) var isMaxWidthAutoResolved: Bool = false
    /// 当前 `estimedSize` 是否为库内部自动推导（可在容器宽度变化时刷新）。
    public private(set) var isEstimedSizeAutoResolved: Bool = false

    /// 库内部专用：写入自动推导的最小宽度，并保留「可刷新」标记。
    mutating func setAutoResolvedMinWidth(_ value: CGFloat?) {
        _minWidth = value
        isMinWidthAutoResolved = true
    }

    /// 库内部专用：写入自动推导的最大宽度，并保留「可刷新」标记。
    mutating func setAutoResolvedMaxWidth(_ value: CGFloat?) {
        _maxWidth = value
        isMaxWidthAutoResolved = true
    }

    /// 库内部专用：写入自动推导的预估尺寸，并保留「可刷新」标记。
    mutating func setAutoResolvedEstimedSize(_ value: CGSize?) {
        _estimedSize = value
        isEstimedSizeAutoResolved = true
    }

    public var placeholderImage: UIImage? = nil
    
    public var extraInfo: Any? = nil
    
    public var textMatch: TextMatch? = nil

    public init() {}
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
            view.onContentSizeChanged = { [weak self] size in
                guard let self = self else { return }
                var newBounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                newBounds = self.adjustAttacmentBounds(newBounds)
                // 注意：这里必须**每次回调时动态读取**当前的最大宽度。
                // 之前是在 beginStreaming 里用 let 捕获了一份快照，
                // 结果横竖屏切换后，附件仍然按旧屏幕宽度裁剪，永远长不大也缩不小。
                newBounds.size.width = min(newBounds.width, self.currentMaxWidth)
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

    /// 当前允许的附件最大宽度。
    ///
    /// 每次使用时实时求值，**不要缓存**——横竖屏切换、分屏、窗口缩放都会改变它。
    private var currentMaxWidth: CGFloat {
        markDownView()?.maxTextWidth ?? UIScreen.main.bounds.width
    }

    /// 容器（MarkdownView）可用宽度发生变化时调用。
    ///
    /// 典型触发时机：横竖屏切换、iPad 分屏 / 台前调度、窗口尺寸变化。
    ///
    /// 做三件事：
    ///   1. 重新推导自动宽度（业务方显式设置的值不动）；
    ///   2. 让子视图按新宽度重新测量（走 `updateViewOptions`）；
    ///   3. 把附件自身的 `bounds` 夹到新的上限内，并通知宿主重排。
    ///
    /// - Returns: 是否发生了实际变化（调用方可据此决定要不要触发重排）。
    @discardableResult
    public func updateForContainerWidthChange() -> Bool {
        // ⚠️ 这两个条件的**顺序不能调换**。
        //
        // `view` 是 lazy 属性，一旦访问就会真的把视图构造出来；
        // 而 `markDownView()` 内部要读 `view.superview`。
        // 所以必须先用 `streamState != .none` 挡掉「尚未开始流式」的附件，
        // 否则会为屏幕外、还没轮到显示的附件提前创建一堆视图。
        //
        // 这些附件也确实不需要在这里处理：它们真正 beginStreaming 时，
        // confiureViewOptions 会用当时最新的宽度重新推导。
        guard streamState != .none, let markdownView = markDownView() else { return false }

        let optionsChanged = resolveAutoWidths(view: view, markdownView: markdownView)
        if optionsChanged {
            view.updateViewOptions(view.viewOptions)
        }

        // 即使 options 没变，也要检查 bounds 是否超出了新的上限
        // （例如从横屏转到竖屏，附件比容器还宽）。
        var newBounds = bounds
        newBounds.size.width = min(newBounds.size.width, currentMaxWidth)
        let boundsChanged = newBounds != bounds
        if boundsChanged {
            bounds = newBounds
        }

        return optionsChanged || boundsChanged
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
        // `frame.origin` 是 TextKit 给出的字形矩形左上角（CGRect 的 origin 永远在视觉左侧，
        // RTL 下也是如此）。要把视图从这个矩形里「内缩」，加的必须是**视觉左侧**那一边的内边距：
        // LTR 时视觉左侧 = leading = left；RTL 时视觉左侧 = trailing = right。
        // 直接写死 `contentInset.left`，在 RTL + 左右不对称内边距时会整体偏移。
        adjustedFrame.origin.x += visualLeftInset(contentInset)
        adjustedFrame.origin.y += contentInset.top
        return adjustedFrame
    }

    /// 当前排版方向下，「视觉左侧」对应的内边距值。
    private func visualLeftInset(_ inset: UIEdgeInsets) -> CGFloat {
        layoutDirection.isRightToLeft ? inset.right : inset.left
    }

    /// 当前排版方向。
    ///
    /// 从 visitor 的样式配置读取，而不是从 `markDownView()`：
    /// 后者依赖 `view.superview?.superview`，在视图尚未挂到父视图上时拿不到。
    private var layoutDirection: MarkdownLayoutDirection {
        markupCtx.visitor.theme.layoutDirection
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

        // 宽度推导单独抽出，容器宽度变化时可以重复执行（见 resolveAutoWidths）。
        resolveAutoWidths(view: view, markdownView: markdownView)
        view.updateViewOptions(view.viewOptions)

        // 下面的 delegate 回调**只在首次配置时触发**。
        // 它们代表业务方的一次性定制（列宽、主题、点击回调等），
        // 容器宽度变化时重复调用会把业务方的运行时状态重置掉。
        notifyConfigureDelegate(view: view, markdownView: markdownView)

        // delegate 里业务方可能改写了 viewOptions（例如指定固定 maxWidth）。
        // 上面那次 updateViewOptions 发生在回调之前，拿不到这些改动，
        // 必须再同步一次，否则业务方设的宽度只存进了 viewOptions、从未生效。
        // 各视图的 updateViewOptions 都对「值没变」做了短路，重复调用无副作用。
        view.updateViewOptions(view.viewOptions)
    }

    /// 根据 MarkdownView 当前的可用宽度，推导附件视图的 min / max / 预估宽度。
    ///
    /// 只会覆盖「库内部自动推导」的值；业务方显式设置过的宽度原样保留
    /// （判定依据见 `ViewOption.isMaxWidthAutoResolved` 等标记）。
    ///
    /// - Returns: 本次是否真的改动了 `viewOptions`。
    @discardableResult
    private func resolveAutoWidths(view: ViewLoadable, markdownView: MarkdownView) -> Bool {

        let inset = view.attachmentContentInset()
        let textViewInset = markdownView.textView.textContainerInset
        // 附件视图可用宽度 = MarkdownView 的文本宽度，减去：
        // textView 内边距 + 文本容器的 lineFragmentPadding（左右各一份）+ 附件自身内边距
        let chrome = textViewInset.left + textViewInset.right
            + markdownView.textView.textContainer.lineFragmentPadding * 2
            + inset.left + inset.right

        var changed = false

        // 首次（还没有值）或「上次也是自动推导的」才更新。
        if view.viewOptions.maxWidth == nil || view.viewOptions.isMaxWidthAutoResolved {
            let resolved = markdownView.maxTextWidth - chrome
            if view.viewOptions.maxWidth != resolved {
                view.viewOptions.setAutoResolvedMaxWidth(resolved)
                changed = true
            } else if view.viewOptions.maxWidth == nil {
                view.viewOptions.setAutoResolvedMaxWidth(resolved)
                changed = true
            }
        }

        if view.viewOptions.minWidth == nil || view.viewOptions.isMinWidthAutoResolved {
            let resolved = markdownView.minTextWidth - chrome
            if view.viewOptions.minWidth != resolved {
                view.viewOptions.setAutoResolvedMinWidth(resolved)
                changed = true
            } else if view.viewOptions.minWidth == nil {
                view.viewOptions.setAutoResolvedMinWidth(resolved)
                changed = true
            }
        }

        if view.viewOptions.estimedSize == nil || view.viewOptions.isEstimedSizeAutoResolved {
            let width = view.viewOptions.maxWidth ?? ViewOption.defaultValue
            // 高度沿用已有值，避免把已经测量出来的真实高度重置成占位值。
            let height = view.viewOptions.estimedSize?.height ?? 100
            let resolved = CGSize(width: width, height: height)
            if view.viewOptions.estimedSize != resolved {
                view.viewOptions.setAutoResolvedEstimedSize(resolved)
                changed = true
            }
        }

        return changed
    }

    private func notifyConfigureDelegate(view: ViewLoadable, markdownView: MarkdownView) {
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
        let ctx = MarkupContext(markup: typed, visitor: markupCtx.visitor,match: markupCtx.match,isClosed: markupCtx.isClosed)
        view.startStreaming(data: ctx, animation: animation)
    }
    
    public func estimatedSize<V: ViewLoadable>(_ view: V)-> CGSize {
        guard let typed = markupCtx.markup as? V.MarkupType else { return .zero}
        let ctx = MarkupContext(markup: typed, visitor: markupCtx.visitor,match: markupCtx.match,isClosed: markupCtx.isClosed)
    
       return view.estimatedSize(for: ctx)
    }
    public func updataData<V: ViewLoadable>(_ view: V) {
        guard let typed = markupCtx.markup as? V.MarkupType else { return}
        let ctx = MarkupContext(markup: typed, visitor: markupCtx.visitor,match: markupCtx.match,isClosed: markupCtx.isClosed)
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
