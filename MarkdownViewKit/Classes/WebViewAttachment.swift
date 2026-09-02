//
//  WebViewAttachment.swift
//  MarkdownViewKit
//
//  一个「块级」流式文本附件：在富文本里为「Web 渲染块」（mermaid / echarts 等）
//  预留空间（占位空白，不绘制内容），真正的 `MarkdownWebBlockView`（内含 WKWebView）
//  作为覆盖视图叠加在占位区域上方。
//
//  加载流程：
//    - 由外部传入 markdown 片段（例如围栏代码块内容 + 语言），
//      通过 `Html.makeHTML(from:)` 转换为可渲染 HTML；
//    - 内嵌 WKWebView 加载 HTML（baseURL = mainBundle，便于访问本地 JS/CSS）；
//    - 通过 KVO 观察 WKWebView 的 scrollView.contentSize 变化，
//      同步更新附件 bounds 并回调宿主重新排版，实现「Web 高度增长 → 富文本高度增长」。
//

import UIKit
import WebKit

// MARK: - 配置

/// `WebViewAttachment` / `MarkdownWebBlockView` 的样式与行为配置。
@available(iOS 13.0, *)
public struct WebViewOption {

    /// 最大宽度（<=0 表示用宿主可用宽度）。
    public var maxWidth: CGFloat = 0
    /// 最大高度（<=0 表示不限制，超出可垂直滚动）。
    public var maxHeight: CGFloat = 0
    /// 初始 / 占位高度（Web 加载前预留空间）。
    public var placeholderHeight: CGFloat = 120

    /// Web 内容背景色。
    public var backgroundColor: UIColor = .clear
    /// 边框颜色。
    public var borderColor: UIColor = UIColor(white: 0.85, alpha: 1)
    /// 圆角。
    public var cornerRadius: CGFloat = 8
    /// WKWebView 内部是否允许滚动（关闭后由外部随内容高度撑开）。
    public var scrollEnabled: Bool = false

    public init() {}
}

// MARK: - 附件

@available(iOS 13.0, *)
public class WebViewAttachment: BaseAttachment {

    /// 待渲染的 Markdown 片段（会通过 `Html.makeHTML(from:)` 转成 HTML）。
    public var markdown: String {
        get {
            codeBlockMatch.content
        }
    }
    
    public var codeBlockMatch: CodeBlockMatch {
        didSet {
            if codeBlockMatch.isClosed {
                let isClose = customView?.webView.isClosed ?? false
                if !isClose {
                    customView?.webView.isClosed = true
                    customView?.loadMarkdown(markdown)
                    customView?.webView.showsShimmer = false
                }
            }
        }
    }

    /// 配置。
    public var configuration: WebViewOption

    public override var view: UIView? {
        get { return customView }
        set { super.view = newValue }
    }

    public lazy var customView: MarkdownWebBlockView? = {
        let v = self.makeWebBlockView()
        v.backgroundColor = .clear
        v.clipsToBounds = true
        return v
    }()

    /// - Parameters:
    ///   - markdown: 待渲染的 Markdown 片段。
    ///   - configuration: 样式与行为配置。
//    public init(markdown: String, configuration: WebViewOption) {
//        self.markdown = markdown
//        self.configuration = configuration
//        super.init(data: nil, ofType: nil)
//        // 用空图 + 0 尺寸占位，真实尺寸在 beginStreaming 里按宿主宽度计算后回填。
//        self.image = UIImage()
//        self.bounds = CGRect(x: 0, y: 0, width: 0, height: 0)
//    }
    
    public init(codeMatch: CodeBlockMatch, configuration: WebViewOption) {
        self.codeBlockMatch = codeMatch
        self.configuration = configuration
        super.init(data: nil, ofType: nil)
        // 用空图 + 0 尺寸占位，真实尺寸在 beginStreaming 里按宿主宽度计算后回填。
        self.image = UIImage()
        self.bounds = CGRect(x: 0, y: 0, width: 0, height: 0)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: 构建视图

    private func makeWebBlockView() -> MarkdownWebBlockView {
        let v = MarkdownWebBlockView()
        v.clipsToBounds = true
        v.layer.cornerRadius = configuration.cornerRadius
        v.layer.borderWidth = 1
        v.layer.borderColor = configuration.borderColor.cgColor
        applyConfiguration(to: v)
        return v
    }

    private func applyConfiguration(to v: MarkdownWebBlockView) {
        v.contentBackgroundColor = configuration.backgroundColor
        v.maxViewHeight = configuration.maxHeight
        v.scrollEnabledInWebView = configuration.scrollEnabled
    }

    // MARK: - StreamingBlockAttachment

    public override func beginStreaming(
        in hostView: UIView,
        frame: CGRect,
        animated: Bool,
        onLayoutChange: @escaping (AttachmentLoadable) -> Void,
        completion: @escaping () -> Void
    ) {
        guard let customView = customView else { return }
        hostView.addSubview(customView)

        let available = configuration.maxWidth > 0 ? configuration.maxWidth : frame.width
        applyConfiguration(to: customView)

        // 先按占位高度落位，等 WKWebView 加载完成后再根据内容尺寸调整。
        let placeholderH = configuration.placeholderHeight
        self.bounds = CGRect(x: 0, y: 0, width: available, height: placeholderH)
        customView.frame = CGRect(x: frame.origin.x, y: frame.origin.y,
                                  width: available, height: placeholderH)

        // 内容尺寸变化时（Web 渲染完成 / 布局变化）：同步更新附件 bounds 并请求宿主重新排版。
        customView.onContentSizeChanged = { [weak self] size in
            guard let self = self else { return }
            var h = size.height
            if self.configuration.maxHeight > 0 {
                h = min(h, self.configuration.maxHeight)
            }
            let newBounds = CGRect(x: 0, y: 0, width: available, height: max(1, h))
            if newBounds.size != self.bounds.size {
                self.bounds = newBounds
                onLayoutChange(self)
            }
        }
        customView.layoutIfNeeded()
        // 装载 HTML。
        customView.loadMarkdown(markdown)
        // Web 渲染不做逐字暂停，立即通知宿主继续后续文字。
        completion()
    }

    public override func updateViewFrame(_ frame: CGRect, in hostView: UIView) {
        super.updateViewFrame(frame, in: hostView)
    }

    public override func removeView() {
        customView?.onContentSizeChanged = nil
        customView?.tearDown()
        customView?.removeFromSuperview()
        customView = nil
        super.removeView()
        onLayoutChange = nil
    }
}

// MARK: - 承载 WKWebView 的容器视图

