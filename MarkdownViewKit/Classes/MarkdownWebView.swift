//
//  MarkdownWebView.swift
//  MarkdownViewKit
//
//  一个可复用的自定义 WKWebView：
//    1) 通过 block 暴露常用代理事件（导航、UI、脚本消息、加载进度、标题变化等），
//       调用方不需要实现 WKNavigationDelegate / WKUIDelegate / WKScriptMessageHandler。
//    2) 重写 `intrinsicContentSize`，把 `scrollView.contentSize` 作为 web 内容的自然尺寸，
//       并在 min/max 约束内自适应；供 AutoLayout / stack view 直接吃到高度。
//    3) 外部可配置 `minWidth / maxWidth / minHeight / maxHeight`；`0` 表示不限制。
//    4) 内容尺寸变化（KVO scrollView.contentSize）时：
//         - 触发 `onContentSizeChanged` 回调；
//         - 调 `invalidateIntrinsicContentSize()`；
//         - 满足条件时对外发一次 `.mdWebViewContentSizeDidChange` 通知，
//           方便非直接持有者也能监听。
//
//  用法示例：
//    let web = MarkdownWebView()
//    web.maxHeight = 600
//    web.onDidFinishLoad = { web in print("loaded") }
//    web.onContentSizeChanged = { web, size in print("size:", size) }
//    web.loadHTMLString(html, baseURL: nil)
//

import UIKit
import WebKit

// MARK: - 通知

public extension Notification.Name {
    /// `MarkdownWebView` 内容尺寸变化通知。
    /// - object: 触发通知的 `MarkdownWebView` 实例。
    /// - userInfo: `["size": NSValue(CGSize)]`。
    static let mdWebViewContentSizeDidChange =
        Notification.Name("MarkdownWebView.contentSizeDidChange")
}

// MARK: - MarkdownWebView

public final class MarkdownWebView: WKWebView {

    // MARK: 尺寸约束（外部可配置；0 = 不限制）

    /// 最小宽度。`0` 表示不限制。
    public var minWidth: CGFloat = 0 {
        didSet { if oldValue != minWidth { invalidateIntrinsicContentSize() } }
    }
    /// 最大宽度。`0` 表示不限制。
    public var maxWidth: CGFloat = 0 {
        didSet { if oldValue != maxWidth { invalidateIntrinsicContentSize() } }
    }
    /// 最小高度。`0` 表示不限制。
    public var minHeight: CGFloat = 0 {
        didSet { if oldValue != minHeight { invalidateIntrinsicContentSize() } }
    }
    /// 最大高度。`0` 表示不限制。
    public var maxHeight: CGFloat = 0 {
        didSet { if oldValue != maxHeight { invalidateIntrinsicContentSize() } }
    }

    // MARK: 事件回调（block 形式暴露的"代理"）

    /// 开始加载。
    public var onDidStartLoad: ((MarkdownWebView) -> Void)?
    /// 加载完成。
    public var onDidFinishLoad: ((MarkdownWebView) -> Void)?
    /// 加载失败（含 provisional 阶段）。
    public var onDidFailLoad: ((MarkdownWebView, Error) -> Void)?
    /// 决定导航策略：返回 `.cancel` 可拦截跳转。默认放行。
    public var onDecidePolicy: ((MarkdownWebView, WKNavigationAction) -> WKNavigationActionPolicy)?
    /// 收到 JS 通过 `window.webkit.messageHandlers.<name>.postMessage(...)` 发来的消息。
    /// 需要先调用 `register(scriptMessageName:)` 注册接收的名字。
    public var onScriptMessage: ((MarkdownWebView, WKScriptMessage) -> Void)?
    /// 加载进度变化（0.0 ~ 1.0）。
    public var onEstimatedProgressChanged: ((MarkdownWebView, Double) -> Void)?
    /// 网页 `<title>` 变化。
    public var onTitleChanged: ((MarkdownWebView, String?) -> Void)?
    /// 内容尺寸变化（来自 `scrollView.contentSize` KVO）。
    public var onContentSizeChanged: ((MarkdownWebView, CGSize) -> Void)?
    /// 内容高度变化（便捷回调，只关心高度时使用）。
    public var onContentHeightChanged: ((MarkdownWebView, CGFloat) -> Void)?
    /// 内建的 JS confirm / alert / prompt 弹窗需要外部处理时用（可选）。
    public var onJSAlert: ((MarkdownWebView, String, @escaping () -> Void) -> Void)?

    /// 是否对外派发 `.mdWebViewContentSizeDidChange` 通知，默认开启。
    public var postsContentSizeNotifications: Bool = true

    // MARK: 光晕动画（转发给 ShimmerOverlayView）

    /// 是否显示叠加在 WebView 上方的光晕动画。默认 `false`。
    /// 打开时会挂一个 `ShimmerOverlayView` 到最上层做循环动画，常用于「加载中 / 生成中」提示。
    public var showsShimmer: Bool = false {
        didSet {
            guard oldValue != showsShimmer else { return }
            updateShimmerOverlay()
        }
    }

    /// 光晕主色（高光色）。默认半透明蓝，在浅色 / 深色页面上都能看到。
    public var shimmerHighlightColor: UIColor = UIColor(red: 0.36, green: 0.62, blue: 1.0, alpha: 0.55) {
        didSet { shimmerOverlayView.highlightColor = shimmerHighlightColor }
    }

    /// 光晕辉光边框颜色。默认淡蓝色。
    public var shimmerGlowColor: UIColor = UIColor(red: 0.36, green: 0.62, blue: 1.0, alpha: 0.9) {
        didSet { shimmerOverlayView.glowColor = shimmerGlowColor }
    }

    /// 光带扫过一次的时长（秒）。默认 1.6。
    public var shimmerDuration: TimeInterval = 1.6 {
        didSet { shimmerOverlayView.duration = shimmerDuration }
    }

    /// 承载光晕的 overlay 视图。用独立 UIView 而不是直接在 self.layer 上加 CALayer，
    /// 是为了绕过 WKWebView 内部 WKContentView 的层级覆盖，保证光晕永远在 web 内容之上。
    private lazy var shimmerOverlayView: ShimmerOverlayView = {
        let v = ShimmerOverlayView()
        v.highlightColor = shimmerHighlightColor
        v.glowColor = shimmerGlowColor
        v.duration = shimmerDuration
        v.translatesAutoresizingMaskIntoConstraints = true
        return v
    }()

    // MARK: 私有

    private var contentSizeObservation: NSKeyValueObservation?
    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

    private var lastContentSize: CGSize = .zero
    /// 已注册的脚本消息名（用于 deinit 里清理）。
    private var registeredScriptMessageNames: Set<String> = []
    private lazy var proxy = InternalProxy(owner: self)
    
    public var isClosed: Bool = false

    // MARK: 初始化

    public convenience init() {
        self.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    public override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        scrollView.backgroundColor = .clear
        scrollView.bounces = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        // 默认关闭内部滚动（尺寸自适应场景常见需求），业务需要时可再打开。
        scrollView.isScrollEnabled = false
        // 关掉双指缩放，避免手势引发 layout 反复。
        scrollView.pinchGestureRecognizer?.isEnabled = false

        navigationDelegate = proxy
        uiDelegate = proxy

        setupObservations()
        showsShimmer = true
    }

    deinit {
        contentSizeObservation?.invalidate()
        progressObservation?.invalidate()
        titleObservation?.invalidate()
        // 清理已注册的脚本消息，避免 WKUserContentController 强持有代理造成泄漏。
        for name in registeredScriptMessageNames {
            configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    // MARK: KVO

    private func setupObservations() {
        contentSizeObservation = scrollView.observe(
            \.contentSize,
             options: [.old, .new]
        ) { [weak self] sv, change in
            guard let self = self else { return }
            let newSize = change.newValue ?? sv.contentSize
            let oldSize = change.oldValue ?? .zero
            guard newSize != oldSize, newSize.height >= 0 else { return }
            self.handleContentSizeChanged(newSize)
        }
        progressObservation = observe(
            \.estimatedProgress,
             options: [.new]
        ) { [weak self] web, change in
            guard let self = self else { return }
            self.onEstimatedProgressChanged?(self, change.newValue ?? web.estimatedProgress)
        }
        titleObservation = observe(
            \.title,
             options: [.new]
        ) { [weak self] web, change in
            guard let self = self else { return }
            self.onTitleChanged?(self, change.newValue ?? web.title)
        }
    }

    private func handleContentSizeChanged(_ size: CGSize) {
        // 与上次差距过小视为抖动，忽略。
        if abs(size.height - lastContentSize.height) < 0.5,
           abs(size.width - lastContentSize.width) < 0.5 {
            return
        }
        lastContentSize = size
        invalidateIntrinsicContentSize()
        onContentSizeChanged?(self, size)
        if size.height != lastContentSize.height {
            // no-op
        }
        onContentHeightChanged?(self, clampedHeight(size.height))
        if postsContentSizeNotifications {
            NotificationCenter.default.post(
                name: .mdWebViewContentSizeDidChange,
                object: self,
                userInfo: ["size": NSValue(cgSize: size)]
            )
        }
    }

    // MARK: intrinsicContentSize

    public override var intrinsicContentSize: CGSize {
        let raw = scrollView.contentSize
        let w = clampedWidth(raw.width)
        let h = clampedHeight(raw.height)
        return CGSize(
            width: w > 0 ? w : UIView.noIntrinsicMetric,
            height: h > 0 ? h : UIView.noIntrinsicMetric
        )
    }

    private func clampedWidth(_ w: CGFloat) -> CGFloat {
        var v = w
        if minWidth > 0 { v = max(v, minWidth) }
        if maxWidth > 0 { v = min(v, maxWidth) }
        return v
    }
    private func clampedHeight(_ h: CGFloat) -> CGFloat {
        var v = h
        if minHeight > 0 { v = max(v, minHeight) }
        if maxHeight > 0 { v = min(v, maxHeight) }
        return v
    }

    // MARK: 光晕 overlay 装配

    public override func layoutSubviews() {
        super.layoutSubviews()
        // overlay 跟随 bounds，并保持在最上层。
        if shimmerOverlayView.superview === self {
            shimmerOverlayView.frame = bounds
            bringSubviewToFront(shimmerOverlayView)
        }
    }

    private func updateShimmerOverlay() {
        if showsShimmer {
            shimmerOverlayView.frame = bounds
            if shimmerOverlayView.superview !== self {
                addSubview(shimmerOverlayView)
            }
            bringSubviewToFront(shimmerOverlayView)
            shimmerOverlayView.isAnimating = true
        } else {
            shimmerOverlayView.isAnimating = false
            shimmerOverlayView.removeFromSuperview()
        }
    }

    // MARK: 脚本消息注册

    /// 注册一个 JS → native 的消息通道。
    /// 之后可以在 JS 中通过
    /// `window.webkit.messageHandlers.<name>.postMessage(payload)` 发送消息，
    /// 消息会在 `onScriptMessage` 回调里收到。
    public func register(scriptMessageName name: String) {
        guard !registeredScriptMessageNames.contains(name) else { return }
        configuration.userContentController.add(proxy, name: name)
        registeredScriptMessageNames.insert(name)
    }

    /// 取消注册一个脚本消息通道。
    public func unregister(scriptMessageName name: String) {
        guard registeredScriptMessageNames.contains(name) else { return }
        configuration.userContentController.removeScriptMessageHandler(forName: name)
        registeredScriptMessageNames.remove(name)
    }
}

// MARK: - 内部代理转发（弱引用 owner，避免循环引用）

private final class InternalProxy: NSObject,
                                   WKNavigationDelegate,
                                   WKUIDelegate,
                                   WKScriptMessageHandler {

    weak var owner: MarkdownWebView?
    init(owner: MarkdownWebView) { self.owner = owner }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 didStartProvisionalNavigation navigation: WKNavigation!) {
        guard let owner = owner else { return }
        owner.onDidStartLoad?(owner)
    }

    func webView(_ webView: WKWebView,
                 didFinish navigation: WKNavigation!) {
        guard let owner = owner else { return }
        owner.onDidFinishLoad?(owner)
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        guard let owner = owner else { return }
        owner.onDidFailLoad?(owner, error)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard let owner = owner else { return }
        owner.onDidFailLoad?(owner, error)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let owner = owner else {
            decisionHandler(.allow); return
        }
        if let decide = owner.onDecidePolicy {
            decisionHandler(decide(owner, navigationAction))
        } else {
            decisionHandler(.allow)
        }
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        guard let owner = owner, let handler = owner.onJSAlert else {
            completionHandler(); return
        }
        handler(owner, message, completionHandler)
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let owner = owner else { return }
        owner.onScriptMessage?(owner, message)
    }
}
