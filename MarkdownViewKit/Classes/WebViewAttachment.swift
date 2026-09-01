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
        didSet {
            customView?.loadMarkdown(markdown)
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
    public init(markdown: String, configuration: WebViewOption) {
        self.markdown = markdown
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

@available(iOS 13.0, *)
public final class MarkdownWebBlockView: UIView {

    /// 内容尺寸变化回调（由 JS postMessage 或 KVO 触发）。
    var onContentSizeChanged: ((CGSize) -> Void)?

    /// 最大高度（<=0 表示不限制）。
    var maxViewHeight: CGFloat = 0

    /// WKWebView 内部是否可滚动。
    var scrollEnabledInWebView: Bool = false {
        didSet { webView.scrollView.isScrollEnabled = scrollEnabledInWebView }
    }

    /// Web 内容背景色。
    var contentBackgroundColor: UIColor = .clear {
        didSet {
            backgroundColor = contentBackgroundColor
            webView.backgroundColor = contentBackgroundColor
            webView.isOpaque = false
            webView.scrollView.backgroundColor = contentBackgroundColor
        }
    }

    private static let heightMessageName = "mdContentHeight"

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        // 注册 JS → native 的消息通道：权威高度来源。
        config.userContentController.add(MessageProxy(target: self),
                                         name: MarkdownWebBlockView.heightMessageName)
        let w = WKWebView(frame: .zero)
        w.translatesAutoresizingMaskIntoConstraints = false
        w.backgroundColor = .clear
        w.isOpaque = false
        w.scrollView.backgroundColor = .clear
        w.scrollView.isScrollEnabled = false
        w.scrollView.bounces = false
        w.scrollView.showsVerticalScrollIndicator = false
        w.scrollView.showsHorizontalScrollIndicator = false
        // 禁掉双指缩放，避免 tap / pinch 触发布局反复。
        w.scrollView.pinchGestureRecognizer?.isEnabled = false
        return w
    }()

    private var contentSizeObservation: NSKeyValueObservation?
    private var lastReportedHeight: CGFloat = 0
    /// 是否已经从 JS 收到过权威高度（收到后 KVO 只在明显更大时才补报）。
    private var receivedJSHeight: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setupObservers()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { tearDown() }

    // MARK: - 加载 HTML

    /// 用 Markdown 片段生成 HTML 并加载到 WKWebView。
    func loadMarkdown(_ markdown: String) {
        receivedJSHeight = false
        lastReportedHeight = 0
        let html = Html.makeHTML(from: markdown)
        webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
    }

    /// 释放 KVO / 消息通道。
    func tearDown() {
        contentSizeObservation?.invalidate()
        contentSizeObservation = nil
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: MarkdownWebBlockView.heightMessageName)
    }

    // MARK: - JS 上报的权威高度

    fileprivate func handleJSHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        receivedJSHeight = true
        reportHeight(height, allowShrink: true)
    }

    // MARK: - KVO 兜底：只在 JS 未上报或明显不足时补一次

    private func setupObservers() {
        return
        contentSizeObservation = webView.scrollView.observe(
            \.contentSize,
             options: [.old,.new]
        ) { [weak self] scrollView, change in
            guard let self = self else { return }
            let newSize = change.newValue ?? scrollView.contentSize
            let oldSize = change.oldValue ?? scrollView.contentSize
            if oldSize == newSize { return }
            guard newSize.height > 0 else { return }
            // 收到过 JS 高度后，KVO 只在明显比已上报高度大很多时才补报（防抖动反馈环）。
            if self.receivedJSHeight {
                if newSize.height > self.lastReportedHeight + 8 {
                    self.reportHeight(newSize.height, allowShrink: false)
                }
            } else {
                self.reportHeight(newSize.height, allowShrink: false)
            }
        }
    }

    private func reportHeight(_ rawHeight: CGFloat, allowShrink: Bool) {
        var h = rawHeight
        if maxViewHeight > 0 {
            h = min(h, maxViewHeight)
        }
        // 抖动阈值：小于阈值的变化直接忽略，防止 1~2px 的循环放大。
        if abs(h - lastReportedHeight) < 2 { return }
        // 不允许缩小（避免瞬时布局收缩再变大）时，仅在更大时上报。
//        if !allowShrink, h < lastReportedHeight { return }
        lastReportedHeight = h
        let width = bounds.width > 0 ? bounds.width : webView.scrollView.contentSize.width
        let size = CGSize(width: width, height: h)
        self.onContentSizeChanged?(size)

    }
    public override func layoutSubviews() {
        super.layoutSubviews()
        
    }
}

// MARK: - 弱引用代理，避免 WKUserContentController 强持有 view 造成循环引用

@available(iOS 13.0, *)
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: MarkdownWebBlockView?
    init(target: MarkdownWebBlockView) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "mdContentHeight" else { return }
        var h: CGFloat = 0
        if let n = message.body as? NSNumber { h = CGFloat(truncating: n) }
        else if let d = message.body as? Double { h = CGFloat(d) }
        else if let i = message.body as? Int { h = CGFloat(i) }
        guard h > 0 else { return }
        target?.handleJSHeight(h)
    }
}
