//
//  MarkdownView.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/8/25.
//

import UIKit
import Down
public class MarkdownView: UIView {
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
            tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
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
    }
    
    
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        notifyContentSizeChangeIfNeeded()
        attributedText(textView.attributedText)
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
        guard let mutableAttributedText = text?.mutableCopy() as? NSMutableAttributedString else { return }
        
        let fullRange = NSRange(location: 0, length: mutableAttributedText.length)

        mutableAttributedText.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            if let attachment = value as? ImageAttachment {
               
            } else if let attachment = value as? GridTableAttachment {
              
                
                tableAttachment(attachment: attachment)
                
            }
        }
    }
    func tableAttachment(attachment: GridTableAttachment) {
        let frame = rectForAttachment(at: attachment.range.location)
        attachment.beginStreaming(in: self.textView, frame: frame, animated: false) {
            
        } completion: {
            
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
}
