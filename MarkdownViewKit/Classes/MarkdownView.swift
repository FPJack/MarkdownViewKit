//
//  MarkdownView.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/8/25.
//

import UIKit
import Down
public class MarkdownView: UIView {
    private lazy var observerBounds = ViewBoundsObserver(view: self, handler: { [weak self] view, oldBounds, newBounds in
        guard let self = self else { return }
        self.onContentSizeChange?(self.bounds.size)
    })
    
    private var bufferedText = NSMutableAttributedString()

    /// 底层的文本视图。你可以直接配置它（字体、颜色、内边距……）。
    public private(set) var textView: UITextView!
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
    
    
    /// 正在逐帧显示文字时为 true。
    public private(set) var isStreaming: Bool = false

    /// 当前已显示的字符数。
    public private(set) var visibleLength: Int = 0

    /// 缓冲区中的总字符数（已显示 + 待显示）。
    public var totalLength: Int { bufferedText.length }
    
    
    /// 排版 / 换行所使用的最大宽度。`0` 表示使用视图当前宽度。默认 `0`。
    public var maxTextWidth: CGFloat = 0 {
        didSet { if oldValue != maxTextWidth { notifyContentSizeChangeIfNeeded() } }
    }

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
            let tv = UITextView(frame: bounds)
            tv.isEditable = false
            tv.isScrollEnabled = true
            tv.backgroundColor = .clear
            tv.contentInset = .zero
            tv.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
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
        _ = observerBounds
    }
    
    
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        notifyContentSizeChangeIfNeeded()
        adjustAttachmentFrames(self.textView.attributedText)
    }
    
    public func invalidateContentSize() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
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
    func attributedText(_ text: NSAttributedString?) {
        self.textView.attributedText = text
    }
    public func startStreamingAttributedText(_ attributedText: NSAttributedString) {
//        self.textView.attributedText = attributedText

        stopDisplayLink()
        if attributedText.length > 0 {
            bufferedText.setAttributedString(attributedText)
        }
        startDisplayLink()
    }
    
    func adjustAttachmentFrames(_ attirbutedText: NSAttributedString?) {
        guard let mutableAttributedText = attirbutedText?.mutableCopy() as? NSMutableAttributedString else { return }
        let fullRange = NSRange(location: 0, length: mutableAttributedText.length)
        mutableAttributedText.enumerateAttribute(.attachment, in: fullRange, options: []) {[weak self] value, range, _ in
            guard let self = self else {return}
            if let attachment = value as? AttachmentLoadable {
                let frame = rectForAttachment(at: range.location)
                attachment.updateViewFrame(frame, in: self.textView)
                attachment.beginStreaming(in: self.textView, frame: frame, animated: false) {[weak self] attachment in
                    guard let self = self else {return}
                    self.refreshAttachmentLayout(range)
                } completion: {
                    
                }
            } else if let attachment = value as? ImageAttachment {
                if  attachment.onImageLoaded == nil {
                    attachment.onImageLoaded = {[weak self] _ in
                        self?.refreshAttachmentLayout(range)
                    }
                }
            }
        }
    }
    
    /// 计算某个字符（附件）在 textView 坐标系里的矩形。
    private func rectForAttachment(at index: Int) -> CGRect {
        guard index < textView.textStorage.length else { return .zero }
        let lm = textView.layoutManager
        let tc = textView.textContainer
        lm.ensureLayout(for: tc)
        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: index, length: 1),
                                       actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
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
            return
        }
        charactersPerFrame = max(1, charactersPerFrame)
        visibleLength = min(visibleLength + charactersPerFrame, totalLength)
        let visibleText = bufferedText.attributedSubstring(from: NSRange(location: 0, length: visibleLength))
        textView.attributedText = visibleText
        invalidateContentSize()
    }
    func stopDisplayLink() {
        displayLink.stop()
    }
    func startDisplayLink() {
        displayLink.start()
    }
    private func resetBuffer() {
        stopDisplayLink()
      
    }
}
