import UIKit
import WebKit
import Markdown


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
/// 定义个枚举 网络加载的三种状态
enum WebLoadState {
    case idle
    case loading
    case finished
    case failed
}

@available(iOS 13.0, *)
public class BaseMarkdownWebBlockView: UIView {
    
   
    // 初始占位值：真正的方向会在 updateData / startStreaming 里从 visitor 透传进来。
    var webBlockMatch: WebBlockMatch = WebBlockMatch(title: "",
                                                     content: "",
                                                     isClosed: false,
                                                     direction: .automatic,
                                                     mirrorsDiagramFlow: false)
    
    public var viewOptions: ViewOption = ViewOption()

    
   
    private var webLoadState: WebLoadState = .idle
    
   

    public var onStreamingFinished: (() -> Void)?
    

    /// 内容尺寸变化回调（由网页 JS `sizeHandler.postMessage(height)` 触发）。
    public var onContentSizeChanged: ((CGSize) -> Void)?

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

    /// 与网页里 `window.webkit.messageHandlers.<name>.postMessage(height)` 保持一致。
    private static let heightMessageName = "sizeHandler"

    /// 网页里用于监听尺寸变化并回传给 native 的 JS。
    /// 与用户在 HTML 里内联的脚本等价：即使 HTML 里没写这段，我们也通过
    /// `WKUserScript` 在 documentEnd 时注入一次，保证每次加载都能收到 postMessage。
    private static let heightReporterScript: String = """
    (function(){
        if (window.__mdSizeHandlerInstalled) { return; }
        window.__mdSizeHandlerInstalled = true;
        function getDocHeight(){
            return Math.max(
                document.body ? document.body.scrollHeight : 0,
                document.body ? document.body.offsetHeight : 0,
                document.documentElement ? document.documentElement.scrollHeight : 0,
                document.documentElement ? document.documentElement.offsetHeight : 0
            );
        }
        function sendHeight(){
            try {
                var h = getDocHeight();
                if (window.webkit
                    && window.webkit.messageHandlers
                    && window.webkit.messageHandlers.sizeHandler) {
                    window.webkit.messageHandlers.sizeHandler.postMessage(h);
                }
            } catch(e) {}
        }
        window.__mdSendHeight = sendHeight;
        window.addEventListener('load', sendHeight);
        window.addEventListener('resize', sendHeight);
        // 图片加载后再上报一次，避免图片撑高导致高度漏报。
        try {
            document.querySelectorAll('img').forEach(function(img){
                if (img.complete) { return; }
                img.addEventListener('load', sendHeight);
                img.addEventListener('error', sendHeight);
            });
        } catch(e) {}
        // 有些页面在 documentEnd 时 body 还没排版好，兜底再补几次。
        setTimeout(sendHeight, 0);
        setTimeout(sendHeight, 100);
        setTimeout(sendHeight, 300);
        // 观察 DOM 变化 & 尺寸变化，动态内容（mermaid/echarts/katex）渲染完能刷新。
        try {
            if (window.ResizeObserver && document.documentElement) {
                var ro = new ResizeObserver(function(){ sendHeight(); });
                ro.observe(document.documentElement);
                if (document.body) { ro.observe(document.body); }
            }
        } catch(e) {}
    })();
    """

    public lazy var webView: MarkdownWebView = {
        return makeWebView()
    }()

    private func makeWebView() -> MarkdownWebView {
        let w = MarkdownWebView()
        w.onDidFinishLoad = {[weak self] _ in
            if self?.webBlockMatch.isClosed ?? false {
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    self?.onStreamingFinished?()
                    print("webview did finish load")
                    self?.webView.showsShimmer = false
                }
            }
        }
        w.onDidFailLoad = {[weak self] _, _ in
            if self?.webBlockMatch.isClosed ?? false {
                self?.onStreamingFinished?()
                self?.webView.showsShimmer = false
            }
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

        // 1) 注入 JS，让网页在 load / resize / img.onload / ResizeObserver 时
        //    通过 window.webkit.messageHandlers.sizeHandler.postMessage(h) 回传高度。
        let userScript = WKUserScript(
            source: Self.heightReporterScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        w.configuration.userContentController.addUserScript(userScript)

        // 2) 注册 sizeHandler 消息通道 + 挂回调。
        w.register(scriptMessageName: Self.heightMessageName)
        w.onScriptMessage = { [weak self] _, message in
            guard let self = self,
                  message.name == Self.heightMessageName else { return }
            let h = Self.heightValue(from: message.body)
            self.handleJSHeight(h)
        }
        // 容器背景保持透明，实际颜色由 `contentBackgroundColor` 控制。
        // （这里原本硬编码了一个调试用的 .brown，会让所有 WebView 块都是棕色底。）
        backgroundColor = contentBackgroundColor
        return w
    }

    private var lastReportedHeight: CGFloat = 0

    /// 上一次已生效的容器宽度，用于识别「宽度真的变了」。
    private var lastAppliedMaxWidth: CGFloat?

    /// 容器可用宽度变化（横竖屏切换 / 分屏 / 窗口缩放）时调用。
    ///
    /// WebView 的高度是由网页内容排版后回报的，宽度一变高度几乎必然跟着变
    /// （文字重新折行、图表重新布局），所以必须主动触发一次重新测量。
    public func updateViewOptions(_ options: ViewOption) {
        guard let width = options.maxWidth, width > 0,
              width != lastAppliedMaxWidth else { return }

        let isFirstApply = (lastAppliedMaxWidth == nil)
        lastAppliedMaxWidth = width
        // 首次只记录基准值：此时页面还没加载，正常加载流程会完成首次测量。
        guard !isFirstApply else { return }

        // 1) 先把自身宽度调整到位，WebView 内部才会按新视口重新排版。
        var newFrame = frame
        if newFrame.size.width != width {
            newFrame.size.width = width
            frame = newFrame
        }

        // 2) 清掉高度去抖记录。
        //    reportHeight 有 2px 阈值，若新旧高度接近，这次变化会被当成抖动丢弃，
        //    结果就是宽度更新了、高度却还停在旧值上。
        lastReportedHeight = 0

        // 3) 显式要一次高度。
        //    改 frame 虽然会触发网页的 resize / ResizeObserver，
        //    但 WKWebView 在 frame 变化后的回调时机并不可靠，这里补一刀兜底。
        webView.evaluateJavaScript("window.__mdSendHeight && window.__mdSendHeight();",
                                   completionHandler: nil)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { tearDown() }

    // MARK: - 加载 HTML

    /// 用 Markdown 片段生成 HTML 并加载到 WKWebView。
    func loadMarkdown(_ markdown: String,htmlKind: Html.ContentKind) {
        if webLoadState == .finished {return}
        if webLoadState == .loading, !webBlockMatch.isClosed {return}
        lastReportedHeight = 0
        // 方向要在启动光晕之前同步：RTL 下加载光带需要从右往左扫，
        // 与内容的生成 / 阅读方向保持一致。
        webView.layoutDirection = webBlockMatch.direction
        let isClosed = webBlockMatch.isClosed
        if isClosed {
            print("webview loading html")
            webView.loadHTMLString(webBlockMatch.htmlContent, baseURL: Bundle.main.bundleURL)
            webLoadState = .finished
        } else {
            print("webview loading placeholder")
            webLoadState = .loading
            webView.showsShimmer = true
            webView.loadHTMLString(webBlockMatch.placeholderHtml, baseURL: Bundle.main.bundleURL)
        }
    }

    /// 释放消息通道。
    func tearDown() {
        webView.unregister(scriptMessageName: Self.heightMessageName)
    }
   

    // MARK: - JS 上报的权威高度

    fileprivate func handleJSHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        reportHeight(height)
    }

    private func reportHeight(_ rawHeight: CGFloat) {
        var h = rawHeight
        if maxViewHeight > 0 {
            h = min(h, maxViewHeight)
        }
        // 抖动阈值：小于阈值的变化直接忽略，防止 1~2px 的循环放大。
        if abs(h - lastReportedHeight) < 2 { return }
        lastReportedHeight = h
//        let width = bounds.width > 0 ? bounds.width : webView.scrollView.contentSize.width
        let width = viewOptions.maxWidth ?? ViewOption.defaultValue
        let size = CGSize(width: width, height: h)
//        onContentSizeChanged?(size)
        bounds = CGRect(origin: bounds.origin, size: size)
    }

    // MARK: - 工具

    private static func heightValue(from body: Any) -> CGFloat {
        if let n = body as? NSNumber { return CGFloat(truncating: n) }
        if let d = body as? Double   { return CGFloat(d) }
        if let i = body as? Int      { return CGFloat(i) }
        if let s = body as? String, let d = Double(s) { return CGFloat(d) }
        return 0
    }
}


@available(iOS 13.0, *)
public  class MarkdownWebBlockView: BaseMarkdownWebBlockView,ViewLoadable {
    public func updateData(data: MarkupContext<Markdown.CodeBlock>) {
        let markup = data.markup
        let isClose = data.isClosed ?? true
        webBlockMatch = WebBlockMatch(title: markup.language ?? "",
                                      content: markup.code,
                                      isClosed: isClose,
                                      direction: data.visitor.theme.layoutDirection,
                                      mirrorsDiagramFlow: data.visitor.theme.mirrorsDiagramFlowInRightToLeft)
        loadMarkdown(webBlockMatch.content, htmlKind: webBlockMatch.hmtlKind)
    }
    
    public func startStreaming(data: MarkupContext<Markdown.CodeBlock>, animation: Bool) {
        let markup = data.markup
        let isClose = data.isClosed ?? true
        webBlockMatch = WebBlockMatch(title: markup.language ?? "",
                                      content: markup.code,
                                      isClosed: isClose,
                                      direction: data.visitor.theme.layoutDirection,
                                      mirrorsDiagramFlow: data.visitor.theme.mirrorsDiagramFlowInRightToLeft)
        loadMarkdown(webBlockMatch.content, htmlKind: webBlockMatch.hmtlKind)
    }
    
    public func estimatedSize(for data: MarkupContext<Markdown.CodeBlock>) -> CGSize {
        viewOptions.estimedSize ?? CGSize(width: ViewOption.defaultValue, height: ViewOption.defaultValue)
    }
    public typealias MarkupType = CodeBlock
}
