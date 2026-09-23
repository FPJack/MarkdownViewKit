//
//  MarkdownView.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/8/25.
//

import UIKit
///定义个枚举流式的四种状态
import Markdown

class TextView: UITextView {
    
}

public typealias MarkupRenderTuple = (
    view: ViewLoadable,
    markdownView: MarkdownView,
    markup: Markup,
    visitor: MarkdownAttributedStringBuilder,
    match: NSTextCheckingResult?
)

public struct MarkupRenderContext<A: ViewLoadable,B: Markup>  {
    
    let view: A

    let markdownView: MarkdownView
    
    let markup: B
    
    let visitor: MarkdownAttributedStringBuilder
    
    /// 自定义正则匹配的结果
    let match: NSTextCheckingResult?

    init(view: A, markdownView: MarkdownView, markup: B, visitor: MarkdownAttributedStringBuilder, match: NSTextCheckingResult?) {
        self.view = view
        self.markdownView = markdownView
        self.markup = markup
        self.visitor = visitor
        self.match = match
    }
}


public protocol MarkdownViewDelegate {
    
    func configureCustomView(_ render: MarkupRenderTuple)
    
    func configureGridTableView(_ render: MarkupRenderContext<GridTableView,Table>)
    
    func configureCodeBlockView(_ render: MarkupRenderContext<CodeBlockView,CodeBlock>)
    
    func configureImageView(_ render: MarkupRenderContext<ImageView,Image>)
    
    func configureCodeWebView(_ render: MarkupRenderContext<MarkdownWebBlockView,CodeBlock>)
    
    func configureLatexWebView(_ render: MarkupRenderContext<LatexWebBlockView,Paragraph>)
    
    func configureHTMLWebView(_ render: MarkupRenderContext<HTMLWebBlockView,HTMLBlock>)
    
}
public extension MarkdownViewDelegate {
    func configureCustomView(_ render: MarkupRenderTuple){}
    
    func configureGridTableView(_ render: MarkupRenderContext<GridTableView,Table>){}
    
    func configureCodeBlockView(_ render: MarkupRenderContext<CodeBlockView,CodeBlock>){}
    
    func configureImageView(_ render: MarkupRenderContext<ImageView,Image>){}
    
    func configureCodeWebView(_ render: MarkupRenderContext<MarkdownWebBlockView,CodeBlock>){}
    
    func configureLatexWebView(_ render: MarkupRenderContext<LatexWebBlockView,Paragraph>){}
    
    func configureHTMLWebView(_ render: MarkupRenderContext<HTMLWebBlockView,HTMLBlock>){}
}



public class MarkdownView: UIView {
    
    public var delegate: MarkdownViewDelegate?

    public lazy var parser: MarkdownParser = {
        var view = MarkdownParser()
        view.markdownView = self
        return view
    }()

    
    private lazy var observerBounds = ViewBoundsObserver(view: self, handler: { [weak self] view, oldBounds, newBounds in
        guard let self = self else { return }
        self.onContentSizeChange?(self.bounds.size)
    })
    
    private var bufferedText = NSMutableAttributedString()

    /// 底层的文本视图。你可以直接配置它（字体、颜色、内边距……）。
    public private(set) var textView: UITextView! {
        didSet {
        }
    }

   
    /// 每一帧（display link）显示的字符数。默认为 1。
    public var charactersPerFrame: Int = 1

    /// 每隔 N 个屏幕帧显示一帧文字。1 = 每帧都显示（最快）。默认为 1。
    public var frameInterval: Int = 1

    /// 纯文本流式时若未指定属性所使用的默认文字属性。
    public var defaultTextAttributes: [NSAttributedString.Key: Any]? = [
        .font: UIFont.systemFont(ofSize: 16.0),
        .foregroundColor: UIColor.black
    ]
    /// 上一次上报的内容尺寸，用于检测宽 / 高变化。
    private var lastContentSize: CGSize = .zero
    
    
//    public var customViewDelegate: CustomViewDelegate?
    
    
    /// 正在逐帧显示文字时为 true。
    public private(set) var isStreaming: Bool = false

    /// 当前已显示的字符数。
    public private(set) var visibleLength: Int = 0 {
        didSet {
        }
    }

    /// 缓冲区中的总字符数（已显示 + 待显示）。
    public var totalLength: Int { bufferedText.length }
    
    
    /// 排版 / 换行所使用的最大宽度。`0` 表示使用视图当前宽度。默认 `0`。
    public var maxTextWidth: CGFloat = 0 {
        didSet {
            guard oldValue != maxTextWidth else { return }
            // 宽度变了：附件需要按新宽度重新测量，不能只刷内容尺寸。
            handleContentWidthChangeIfNeeded()
            notifyContentSizeChangeIfNeeded()
        }
    }

    /// 上一次完成排版时使用的内容宽度，用于检测横竖屏 / 分屏导致的宽度变化。
    private var lastLaidOutContentWidth: CGFloat = 0

    /// 正在处理宽度变化，用于防止 layoutSubviews 递归重入。
    private var isHandlingContentWidthChange = false

    /// 最大高度。上报的内容尺寸高度会被限制到此值（超出部分由文本视图滚动显示）。`0` 表示不限制。默认 `0`。
    public var maxTextHeight: CGFloat = 0 {
        didSet { if oldValue != maxTextHeight { notifyContentSizeChangeIfNeeded() } }
    }

    /// 最小宽度。上报的内容尺寸宽度不会小于此值。`0` 表示不限制。默认 `0`。
    public var minTextWidth: CGFloat = 0 {
        didSet { if oldValue != minTextWidth { notifyContentSizeChangeIfNeeded() } }
    }

    /// 最小高度。上报的内容尺寸高度不会小于此值。`0` 表示不限制。默认 `0`。
    public var minTextHeight: CGFloat = 0 {
        didSet { if oldValue != minTextHeight { notifyContentSizeChangeIfNeeded() } }
    }
    
    private lazy var displayLink = {
      let timer =  DisplayLinkTimer(preferredFramesPerSecond: frameInterval) {[weak self] tick in
            
          self?.displayLinkTick(tick)
        }
      return timer
    }()
    
    
    public var onContentSizeChange: ((_ contentSize: CGSize) -> Void)?

    
    var loadableAttachments: [BaseAttachment] = []
    
    
    let queue = DispatchQueue(label: "com.xxx.serial",qos: .userInitiated)
    
    // MARK: - 初始化

    /// 使用指定 frame 与外部传入的自定义 UITextView 进行初始化。
    /// 传入的 textView 会被强制设为不可编辑，其余配置保持不变。
    public init(frame: CGRect, textView: UITextView?) {
        super.init(frame: frame)
        commonInit(with: textView)
    }
    
    /// 使用外部传入的自定义 UITextView 进行初始化。
    public convenience init(textView: UITextView?) {
        self.init(frame: .zero, textView: textView)
    }
   

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit(with: nil)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit(with: nil)
    }

    private func commonInit(with textView: UITextView?) {
        if let tv = textView {
            // 采用外部传入的自定义文本视图，尽量保留其原有配置。
            tv.frame = bounds
            tv.isEditable = false // 流式展示视图不可编辑
            self.textView = tv
        } else {
            let tv = UITextView()

            tv.isEditable = false
            tv.isScrollEnabled = true
            tv.backgroundColor = .clear
            tv.contentInset = .zero
            tv.textContainerInset = .zero
            tv.textContainer.lineFragmentPadding = 5
            tv.backgroundColor = .white
            self.textView = tv
        }
        addSubview(self.textView)
        ///添加约束
        self.textView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.textView.topAnchor.constraint(equalTo: self.topAnchor),
            self.textView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.textView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.textView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
        applyLayoutDirection()
        _ = observerBounds
    }

    // MARK: - 排版方向（RTL 适配）

    /// 当前生效的排版方向。
    ///
    /// 只读：方向统一在样式配置里设置，与字体 / 颜色保持同一套入口——
    /// ```swift
    /// var configuration = MarkdownStylerConfiguration()
    /// configuration.layoutDirection = .rightToLeft
    /// markdownView.parser.theme = configuration
    /// ```
    /// 赋值后会在下一次渲染时自动同步到内部的 `UITextView`。
    public var layoutDirection: MarkdownLayoutDirection {
        parser.styler.configuration.layoutDirection
    }

    /// 把配置里的排版方向同步到 `UITextView`。
    ///
    /// 段落级的镜像（缩进 / 对齐）由 `NSParagraphStyle` 完成，
    /// 这里额外处理两件 TextKit 管不到的事：
    /// 1. `semanticContentAttribute`：影响 textView 自身及其子视图（附件视图）的布局方向；
    /// 2. `textAlignment`：保证未携带段落样式的纯文本也跟随方向。
    ///    注意必须显式写 `.left` / `.right`——`.natural` 跟的是 App 的本地化语言，
    ///    在中文 App 里展示阿拉伯语时会被解析成左对齐。
    func applyLayoutDirection() {
        guard let textView = textView else { return }
        let direction = layoutDirection
        let semantic = direction.semanticContentAttribute
        if textView.semanticContentAttribute != semantic {
            textView.semanticContentAttribute = semantic
        }
        if semanticContentAttribute != semantic {
            semanticContentAttribute = semantic
        }
        let alignment = direction.leadingAlignment
        if textView.textAlignment != alignment {
            textView.textAlignment = alignment
        }
    }

    /// 当前方向下，文本容器「行首一侧」的内边距。
    ///
    /// - Note: 注意**不要**用它来做「文本容器坐标 → textView 坐标」的换算。
    ///   文本容器在 textView 里的原点恒为 `(textContainerInset.left, .top)`，
    ///   与排版方向无关。这个属性只适用于需要区分「行首 / 行尾」的场景。
    var leadingTextContainerInset: CGFloat {
        layoutDirection.isRightToLeft
            ? textView.textContainerInset.right
            : textView.textContainerInset.left
    }
    
    
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        // 先处理宽度变化（横竖屏 / 分屏 / 窗口缩放），再算内容尺寸。
        // 顺序不能反：附件宽度没更新前算出来的 contentSize 是旧的。
        handleContentWidthChangeIfNeeded()
        notifyContentSizeChangeIfNeeded()
        adjustAttachmentFrames(self.textView.attributedText)
    }

    // MARK: - 容器宽度变化（横竖屏切换 / 分屏 / 窗口缩放）

    /// 当前排版实际使用的内容宽度。
    private var effectiveContentWidth: CGFloat {
        let width = maxTextWidth > 0 ? maxTextWidth : textView.bounds.width
        return width > 0 ? width : bounds.width
    }

    /// 宿主主动通知「可用宽度可能变了」。
    ///
    /// 一般不需要手动调用——`layoutSubviews` 会自动检测。
    /// 但在 `viewWillTransition(to:with:)` 里想让重排提前发生时可以显式调用：
    ///
    /// ```swift
    /// override func viewWillTransition(to size: CGSize, with coordinator: ...) {
    ///     super.viewWillTransition(to: size, with: coordinator)
    ///     coordinator.animate(alongsideTransition: { _ in
    ///         self.markdown.maxTextWidth = size.width - 40
    ///         self.markdown.invalidateLayoutForWidthChange()
    ///     })
    /// }
    /// ```
    public func invalidateLayoutForWidthChange() {
        lastLaidOutContentWidth = 0   // 强制下次检测判定为「已变化」
        handleContentWidthChangeIfNeeded()
        notifyContentSizeChangeIfNeeded()
        adjustAttachmentFrames(textView.attributedText)
    }

    /// 检测内容宽度是否变化，变化则让所有附件按新宽度重新测量。
    ///
    /// ## 流式渲染中途旋转
    ///
    /// 这个方法在流式打印过程中也可能被触发，因此必须满足：
    ///
    /// 1. **不打断流式状态**：只通知附件重新测量宽度，不重建数据。
    ///    各子视图的宽度响应也都避开了会重置流式进度的全量 reload
    ///    （见 `GridTableView.relayoutForAvailableWidthChange`）。
    ///
    /// 2. **跳过尚未开始的附件**：`streamState == .none` 的附件会被
    ///    `updateForContainerWidthChange()` 直接跳过。它们的视图是 lazy 创建的，
    ///    提前访问会导致视图被无谓地构造出来；而且它们真正开始流式时
    ///    会用当时的最新宽度重新推导，本来就不需要在这里处理。
    ///
    /// 3. **防重入**：下面的 `invalidateLayout` / `ensureLayout` 会触发
    ///    新一轮 `layoutSubviews`，若不加保护会递归。
    private func handleContentWidthChangeIfNeeded() {
        guard !isHandlingContentWidthChange else { return }

        let width = effectiveContentWidth
        guard width > 0, width != lastLaidOutContentWidth else { return }

        isHandlingContentWidthChange = true
        defer { isHandlingContentWidthChange = false }

        lastLaidOutContentWidth = width

        // 附件（表格 / 代码块 / 图片 / WebView）的宽度是渲染时算好存在
        // attachment.bounds 里的，TextKit 不会自动重算，必须逐个通知。
        var changedRanges: [NSRange] = []
        for attachment in loadableAttachments {
            guard attachment.updateForContainerWidthChange() else { continue }
            if let range = attachment.range { changedRanges.append(range) }
        }

        guard !changedRanges.isEmpty else { return }

        let lm = textView.layoutManager
        for range in changedRanges {
            // 越界保护：流式渲染过程中，附件的 range 可能还没进入当前可见文本，
            // 此时 textStorage 比 bufferedText 短，直接用会崩。
            guard range.location + range.length <= textView.textStorage.length else { continue }
            lm.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        }
        lm.ensureLayout(for: textView.textContainer)
    }
    
    public func invalidateContentSize() {
        self.invalidateIntrinsicContentSize()
        self.setNeedsLayout()
    }
    
    
    private func notifyContentSizeChangeIfNeeded() {
        let size = textContentSize
        if size.equalTo(lastContentSize) { return }
        lastContentSize = size
        invalidateContentSize()
    }
    
    /// 已显示文字实际占用的尺寸（适配当前 / 最大宽度，并限制到最大 / 最小宽高）。
    public var textContentSize: CGSize {
        var width = maxTextWidth > 0 ? maxTextWidth : textView.bounds.width
        if width <= 0 { width = bounds.width }
        if width <= 0 { width = .greatestFiniteMagnitude }

        var height = maxTextHeight > 0 ? maxTextHeight : textView.bounds.height
        if height <= 0 { height = bounds.height }
        if height <= 0 { height = .greatestFiniteMagnitude }

        let fitting = textView.sizeThatFits(CGSize(width: width, height: height))
        var w = ceil(fitting.width)
        var h = ceil(fitting.height)
        if maxTextWidth > 0 { w = min(w, maxTextWidth) }
        if maxTextHeight > 0 { h = min(h, maxTextHeight) }
        if minTextWidth > 0 { w = max(w, minTextWidth) }
        if minTextHeight > 0 { h = max(h, minTextHeight) }
        // 防止把 NaN / 无穷大 传给 Auto Layout（会直接崩溃）。
        if !w.isFinite { w = 0 }
        if !h.isFinite { h = 0 }
        return CGSize(width: w, height: h)
    }

    public override var intrinsicContentSize: CGSize {
        lastContentSize
        
    }

    deinit {
        
    }
}

public extension MarkdownView {
    /// 设置富文本内容（会立即显示全部文字）。
    private func updateLoadableAttachments(_ text: NSAttributedString? ) {
        loadableAttachments.removeAll()
        guard let text = text else { return }
        let fullRange = NSRange(location: 0, length: text.length)
        let mutableAttributedText = NSMutableAttributedString(attributedString: text)
        mutableAttributedText.enumerateAttribute(.attachment, in: fullRange, options: []) {[weak self] value, range, _ in
            guard let self = self else {return}
            if let attachment = value as? BaseAttachment {
                let frame = rectForAttachment(at: range.location)
                attachment.range = range
                self.loadableAttachments.append(attachment)
            }
        }
    }
    func attributedText(_ text: NSAttributedString?) {
        applyLayoutDirection()
        self.textView.attributedText = text
    }
    private func startStreamingAttributedText(_ attributedText: NSAttributedString) {
        updateLoadableAttachments(attributedText)
        stopDisplayLink()
        if attributedText.length > 0 {
            bufferedText.setAttributedString(attributedText)
        }
        startDisplayLink()
    }
    
    public func startStreamingText(markdown: String) {
        applyLayoutDirection()
        let attr = parser.attributedString(from: markdown)
        startStreamingAttributedText(attr)
    }
    
    public func appendText(
        fromMarkdown markdown: String) {
        applyLayoutDirection()
        let attr = parser.appendString(from: markdown)
        replaceAttributedText(attr)
    }
    
    private func replaceAttributedText(_ attributedText: NSAttributedString) {
        bufferedText.setAttributedString(attributedText)
        updateLoadableAttachments(attributedText)
        visibleLength = min(visibleLength, totalLength)
        /// 如果有附件还没有开始流式，就把可见长度限制在第一个附件的起始位置，这样可以确保附件在流式显示之前不会被截断。
        if let attachment = loadableAttachments.first {$0.streamState == .none} {
            visibleLength = min(visibleLength, attachment.range!.location)
        }
        startDisplayLink()
        
        if textView.attributedText.length > bufferedText.length {
            textView.attributedText = bufferedText.attributedSubstring(from: NSRange(location: 0, length: visibleLength))
            invalidateContentSize()
        }
    }
    
    func adjustAttachmentFrames(_ attirbutedText: NSAttributedString?) {
        guard let mutableAttributedText = attirbutedText?.mutableCopy() as? NSMutableAttributedString else { return }
        
        let fullRange = NSRange(location: 0, length: min(visibleLength, attirbutedText?.length ?? 0))
        mutableAttributedText.enumerateAttribute(.attachment, in: fullRange, options: []) {[weak self] value, range, _ in
            guard let self = self else {return}
            if let attachment = value as? BaseAttachment {
                let frame = rectForAttachment(at: range.location)
                attachment.updateViewFrame(frame, in: self.textView)
            }
        }
    }
    
    /// 计算某个字符（附件）在 textView 坐标系里的矩形。
    ///
    /// - Important: 这里**不能**用 `boundingRect(forGlyphRange:in:)`。
    ///
    ///   当传入的字形范围正好覆盖一整行时，`boundingRect` 返回的是
    ///   **整行的 line fragment 矩形**（x = 0、宽度 = 文本容器宽），
    ///   而不是字形自身的位置。
    ///
    ///   而块级附件（图片 / 表格 / 代码块）恰恰都是「独占一行的单个字形」，
    ///   所以拿到的永远是 x = 0：
    ///   - LTR 下行是左对齐的，x = 0 恰好就是正确答案 → 一直没暴露；
    ///   - RTL 下行是右对齐的，附件应该贴右边，却被摆到了 x = 0 → **跳到左边**。
    ///
    ///   （图片加载前占位宽度撑满整行，右边缘恰好重合，所以「看起来在右边」；
    ///   加载完成后宽度缩小，x = 0 的问题立刻显形，表现为「突然跳到左边」。）
    ///
    ///   正确做法是用 `lineFragmentRect` + `location(forGlyphAt:)`：
    ///   后者返回字形相对所在行的位置，**已经把对齐方式算进去了**。
    private func rectForAttachment(at index: Int) -> CGRect {
        guard index < textView.textStorage.length else { return .zero }
        let lm = textView.layoutManager
        let tc = textView.textContainer
        lm.ensureLayout(for: tc)

        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: index, length: 1),
                                       actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return .zero }
        let glyphIndex = glyphRange.location

        guard let attachment = textView.textStorage
            .attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment else {
            return .zero
        }

        let fragmentRect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        // 字形相对行起点的位置：x 已包含对齐产生的偏移，y 是基线偏移。
        let glyphLocation = lm.location(forGlyphAt: glyphIndex)

        // NSTextAttachment.bounds 是「相对基线」的矩形：
        // origin.y 是相对基线的下沉量，附件顶边 = 基线 - (height + origin.y)。
        let size = attachment.bounds.size
        var rect = CGRect(x: fragmentRect.minX + glyphLocation.x,
                          y: fragmentRect.minY + glyphLocation.y - (size.height + attachment.bounds.origin.y),
                          width: size.width,
                          height: size.height)

        // 文本容器在 textView 里的原点固定是 (inset.left, inset.top)，
        // 与排版方向无关，所以这里恒用 left。
        rect.origin.x += textView.textContainerInset.left
        rect.origin.y += textView.textContainerInset.top
        return rect
    }
    
    private func refreshAttachmentLayout(_ range: NSRange) {
        let lm = textView.layoutManager
        lm.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        lm.ensureLayout(for: textView.textContainer)
        invalidateContentSize()
    }
}
extension MarkdownView {
    func displayLinkTick(_ tick: DisplayLinkTimerTick) {
        if visibleLength >= totalLength {
            stopDisplayLink()
            isStreaming = false
            return
        }
        
        let attachmengStreaming = loadableAttachments.first { attachment  in
            return attachment.streamState == .streaming
        }
        guard attachmengStreaming == nil else {return}
        
        isStreaming = true
        charactersPerFrame = max(1, charactersPerFrame)
    
        do {
//            let loadableAttachment = getLoadableAttachment(NSRange(location: visibleLength, length: charactersPerFrame))
            let loadableAttachment = getNextAttachment(NSRange(location: visibleLength, length: charactersPerFrame))
            
            if let loadableAttachment = loadableAttachment {
                if loadableAttachment.range!.location > visibleLength {
                    visibleLength = min(loadableAttachment.range!.location, totalLength)
                    let visibleText = bufferedText.attributedSubstring(from: NSRange(location: 0, length: loadableAttachment.range!.location))
                    textView.attributedText = visibleText
                    invalidateContentSize()
                    return
                }
                
                pauseDisplayLink()
                visibleLength = min(loadableAttachment.range!.location + 1, totalLength)

                let visibleText = bufferedText.attributedSubstring(from: NSRange(location: 0, length: visibleLength))
                textView.attributedText = visibleText
                invalidateContentSize()
                attachmentStarBeginStream(loadableAttachment)
                return
            }
        }
        
        
        visibleLength = min(visibleLength + charactersPerFrame, totalLength)
        let visibleText = bufferedText.attributedSubstring(from: NSRange(location: 0, length: visibleLength))
        textView.attributedText = visibleText
        invalidateContentSize()
    }
    func attachmentStarBeginStream(_ attachment: BaseAttachment) {
        attachment.streamState = .streaming
        let frame = rectForAttachment(at: attachment.range!.location)
        attachment.beginStreaming(in: textView, frame: frame, animated: true) {[weak self] attachment in
            guard let self = self else {return}
            self.refreshAttachmentLayout(attachment.range!)
        } completion: {[weak self] in
            guard attachment.streamState != .finished else {return}
            attachment.streamState = .finished
            guard let self = self else {return}
            self.startDisplayLink()
        }
    }
//    func getLoadableAttachment(_ with: NSRange) -> AttachmentLoadable? {
//        //判断range是包含关系就返回
//        let attach = loadableAttachments.first(where: {
//            if let view = $0.view as? GridTableView {
//                print("getLoadableAttachment: \($0.range!) with \(with)")
//
//            }
//
//           return NSIntersectionRange($0.range!, with).length > 0
//        })
//        if let attach = attach {
//            print("getLoadableAttachment:")
//            print("getLoadableAttachment: \(String(describing: attach.range))")
//        }
//        return attach
//    }
    func getNextAttachment(_ to: NSRange) -> BaseAttachment? {
        ///根据流的状态以及range的包含关系来判断是否返回下一个附件
        let attach = loadableAttachments.first { attachment in
            let state = attachment.streamState
            let range = attachment.range ?? NSRange(location: 0, length: 0)
            if state == .none,range.location < to.location + to.length {
                return true
            }else {
                return false
            }
        }
        return attach
    }

   
    func stopDisplayLink() {
        displayLink.stop()
    }
    func pauseDisplayLink() {
        displayLink.pause()
    }
    func startDisplayLink() {
        displayLink.start()
    }
    private func resetBuffer() {
        stopDisplayLink()
      
    }
}

