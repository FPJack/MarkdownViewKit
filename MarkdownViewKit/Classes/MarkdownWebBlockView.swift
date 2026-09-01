import UIKit
import WebKit
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

    public lazy var webView: MarkdownWebView = {
        return makeWebView()
    }()
    private func makeWebView() ->MarkdownWebView {
        let w = MarkdownWebView()
        w.onDidFinishLoad = { _ in
            print("webview did finish load")
        }
        w.onDidFailLoad = { _,__ in
            print("webview did fail load")
        }
        w.showsShimmer = true
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
    }
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
        print("webview create")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { tearDown() }
    
    

    // MARK: - 加载 HTML

    /// 用 Markdown 片段生成 HTML 并加载到 WKWebView。
    func loadMarkdown(_ markdown: String) {
        let isClosed = webView.isClosed
        if isClosed {
            self.receivedJSHeight = false
            self.lastReportedHeight = 0
            let html = Html.makeHTML(from: markdown)
            self.webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
        }else {
            let htmlStr = """
                ```echarts
                {
                }
                ```
                """
            self.receivedJSHeight = false
            self.lastReportedHeight = 0
            
            
            let emptyHTML = """
                       <!doctype html><html><head>
                         <meta charset="utf-8">
                         <meta name="viewport" content="width=device-width, initial-scale=1">
                         <style>html,body{margin:0;padding:0;background:transparent;}</style>
                       </head><body></body></html>
                       """
            let html = Html.makeHTML(from: htmlStr)
            self.webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
        }
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
        contentSizeObservation = webView.scrollView.observe(
            \.contentSize,
             options: [.old,.new]
        ) { [weak self] scrollView, change in
            guard let self = self else { return }
            let newSize = change.newValue ?? scrollView.contentSize
            let oldSize = change.oldValue ?? scrollView.contentSize
            if oldSize == newSize { return }
            guard newSize.height > 0 else { return }
           
            self.reportHeight(newSize.height, allowShrink: false)
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
//        self.heightCons.constant = size.height
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
