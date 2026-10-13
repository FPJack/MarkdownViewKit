//
//  MathJaxWebView.swift
//  SwiftMarkdownViewKit
//
//  一个「专职把 LaTeX 公式排版成 SVG / UIImage」的工具类。
//
//  ## 它解决什么问题
//
//  库里原本的公式方案（`LatexWebBlockView`）是把 WebView **当作视图**直接插在
//  正文里：每个公式一个 WKWebView。公式一多就会出现进程开销大、高度回报抖动、
//  滚动掉帧等问题，而且 WebView 的内容无法参与 TextKit 的文字排版（没法和
//  行内文字对齐、不能被 NSAttributedString 复制）。
//
//  本类换了一条路：WebView **只作为离屏排版引擎**存在，排完版就把结果以
//  SVG 字符串 + 尺寸 + 基线偏移的形式交还给原生，由原生决定怎么画。
//  因此：
//    · 整个 App 只有一个隐藏 WebView，和公式数量无关；
//    · 产物是普通 UIImage，可直接塞进 `NSTextAttachment` 做**行内公式**；
//    · 带缓存，同一条公式只排版一次。
//
//  ## 最简用法
//
//  ```swift
//  // 块级公式 $$...$$
//  MathJaxWebView.shared.renderImage(#"\frac{-b \pm \sqrt{b^2-4ac}}{2a}"#,
//                                    displayMode: true) { result in
//      imageView.image = try? result.get()
//  }
//
//  // 行内公式 $...$
//  MathJaxWebView.shared.render("E = mc^2", displayMode: false) { result in
//      guard let output = try? result.get() else { return }
//      output.svg             // SVG 字符串
//      output.image           // UIImage
//      output.size            // 逻辑点尺寸
//      output.baselineOffset  // 基线偏移，拿去设 NSTextAttachment.bounds.origin.y
//  }
//
//  // 直接从一段 Markdown 里把所有公式抓出来批量排版
//  let formulas = MathFormula.formulas(in: markdown)
//  MathJaxWebView.shared.render(formulas) { results in ... }
//  ```
//

import UIKit
import WebKit

#if canImport(SDWebImageSVGCoder)
import SDWebImage
import SDWebImageSVGCoder
#endif

// MARK: - 公式模型

/// 一条待排版的数学公式。
public struct MathFormula: Hashable {

    /// LaTeX 源码（**不含** `$`、`$$`、`\(`、`\[` 等定界符）。
    public var latex: String

    /// 是否为块级（display）公式。
    ///
    /// - `true`：对应 `$$...$$` / `\[...\]`，居中、独占一行、求和与积分的上下限排在符号正上下方；
    /// - `false`：对应 `$...$` / `\(...\)`，紧凑排版，上下限排在右侧，适合跟文字混排。
    public var isDisplayMode: Bool

    public init(latex: String, isDisplayMode: Bool) {
        self.latex = latex
        self.isDisplayMode = isDisplayMode
    }
}

// MARK: - 从 Markdown 中抽取公式

public extension MathFormula {

    /// 从一段 Markdown 文本里抽取全部数学公式。
    ///
    /// 支持四种定界符，并按「先块级后行内」的顺序匹配，避免 `$$...$$`
    /// 被行内规则拆成两个空的 `$...$`：
    ///
    /// | 写法 | 类型 |
    /// |---|---|
    /// | `$$...$$` | 块级 |
    /// | `\[...\]` | 块级 |
    /// | `$...$`   | 行内 |
    /// | `\(...\)` | 行内 |
    ///
    /// 已自动规避的误判：
    /// - 代码块（``` 围栏）和行内代码（`` ` ``）里的 `$` 不会被当作公式；
    /// - 转义过的 `\$` 不会触发行内公式；
    /// - 金额写法 `$100` 因为缺少配对的结束 `$`，不会被匹配。
    ///
    /// - Parameter markdown: Markdown 原文。
    /// - Returns: 按出现顺序排列的公式数组（内容重复的会各自保留一份）。
    static func formulas(in markdown: String) -> [MathFormula] {
        let masked = maskingCodeSpans(markdown)
        let text = masked as NSString
        var found: [(range: NSRange, formula: MathFormula)] = []

        // 块级在前：先占住 $$...$$ 的区间，行内规则再在剩余区间里找。
        let patterns: [(pattern: String, display: Bool)] = [
            (#"\$\$([\s\S]+?)\$\$"#, true),
            (#"\\\[([\s\S]+?)\\\]"#, true),
            // (?<!\\) 排除被转义的 \$；[^$\n] 保证行内公式不跨行、不跨越空的 $$
            (#"(?<!\\)\$(?!\$)([^$\n]+?)(?<!\\)\$(?!\$)"#, false),
            (#"\\\(([\s\S]+?)\\\)"#, false)
        ]

        var consumed: [NSRange] = []

        for (pattern, display) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: masked,
                                        range: NSRange(location: 0, length: text.length))
            for match in matches {
                // 跳过已被更高优先级规则吃掉的区间
                guard !consumed.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else {
                    continue
                }
                let body = match.range(at: 1)
                guard body.location != NSNotFound else { continue }

                let latex = text.substring(with: body)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !latex.isEmpty else { continue }

                consumed.append(match.range)
                found.append((match.range,
                              MathFormula(latex: latex, isDisplayMode: display)))
            }
        }

        return found
            .sorted { $0.range.location < $1.range.location }
            .map(\.formula)
    }

    /// 把代码块 / 行内代码的内容替换成等长的空格。
    ///
    /// 用等长占位而不是直接删除，是为了让后续正则匹配出来的 `NSRange`
    /// 仍然能对应回原文位置（本方法只用于匹配，返回的公式文本取自掩码串，
    /// 而掩码串在非代码区与原文逐字符一致，所以内容也是对的）。
    private static func maskingCodeSpans(_ markdown: String) -> String {
        var result = markdown
        let patterns = [
            #"```[\s\S]*?```"#,     // 围栏代码块
            #"~~~[\s\S]*?~~~"#,     // 波浪号围栏
            #"`[^`\n]*`"#           // 行内代码
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let mutable = NSMutableString(string: result)
            let matches = regex.matches(in: result,
                                        range: NSRange(location: 0, length: mutable.length))
            // 倒序替换，避免前面的替换影响后面 range 的有效性
            for match in matches.reversed() {
                let blanks = String(repeating: " ", count: match.range.length)
                mutable.replaceCharacters(in: match.range, with: blanks)
            }
            result = mutable as String
        }
        return result
    }
}

// MARK: - 排版结果

/// 一条公式的排版产物。
public struct MathRenderOutput {

    /// MathJax 生成的 SVG 源码。
    ///
    /// 已经过以下处理，可直接交给任意 SVG 解码器或存成文件：
    /// - `width` / `height` 固化成 **px**（MathJax 原始输出是 `ex`，原生解码器通常不认）；
    /// - `currentColor` 替换成具体颜色值；
    /// - 补齐 `xmlns` 命名空间。
    public let svg: String

    /// 排版后的逻辑点尺寸（已按 `MathRenderOptions.fontSize` 缩放）。
    public let size: CGSize

    /// 行内公式的基线偏移（点）。
    ///
    /// 负值表示公式需要相对基线**下沉**（例如分数、求和的下半部分）。
    /// 用于 `NSTextAttachment`：
    ///
    /// ```swift
    /// attachment.bounds = CGRect(x: 0, y: output.baselineOffset,
    ///                            width: output.size.width,
    ///                            height: output.size.height)
    /// ```
    ///
    /// 块级公式一般为 0。
    public let baselineOffset: CGFloat

    /// 栅格化后的图片。
    ///
    /// 若环境里没有可用的 SVG 解码器（见 `MathJaxWebView.svgDecoder`），
    /// 这里会是 `nil`，但 `svg` 字段始终有效。
    public let image: UIImage?
}

/// 排版参数。
public struct MathRenderOptions {

    /// 公式颜色。默认跟随 `UIColor.label`（自动适配深色模式）。
    ///
    /// - Note: 颜色在排版时就写死进 SVG 了。如果 App 支持深色模式切换，
    ///   切换后需要用新颜色重新排版（`traitCollectionDidChange` 里调一次即可）。
    public var textColor: UIColor = .label

    /// 基准字号（点）。公式整体大小随它等比缩放，通常传正文字号。默认 17。
    public var fontSize: CGFloat = 17

    /// 栅格化倍率。默认取主屏 scale，保证 Retina 下不糊。
    public var scale: CGFloat = UIScreen.main.scale

    /// MathJax 脚本地址。
    ///
    /// - Important: 必须是 **`-svg`** 结尾的发行版（`tex-mml-svg.js` / `tex-chtml-svg.js`），
    ///   因为本类依赖 `MathJax.tex2svg()`。
    ///   常见的 `tex-mml-chtml.js` 输出的是 CommonHTML，**没有** `tex2svg` 方法，
    ///   用它会让每条公式都失败并返回 `.mathJaxUnavailable`。
    ///
    /// 想离线使用：把 `tex-mml-svg.js` 拖进 App Target，本类会自动优先用本地文件
    /// （见 `resolvedScriptTag`），无需改这里。
    public var scriptURL: String = "https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-svg.js"

    /// 单条公式的排版超时（秒）。默认 15，主要用于兜底 CDN 不可达的情况。
    public var timeout: TimeInterval = 15

    public init() {}
}

/// 排版失败原因。
public enum MathRenderError: Error, LocalizedError {

    /// LaTeX 为空。
    case emptyFormula

    /// MathJax 脚本没加载成功，或加载的发行版不含 SVG 输出（常见于误用 `-chtml` 版本）。
    case mathJaxUnavailable

    /// LaTeX 语法错误，附带 MathJax 的报错信息。
    case invalidLatex(String)

    /// 超时。
    case timeout

    /// WebView 自身加载失败。
    case webViewFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .emptyFormula:
            return "公式内容为空"
        case .mathJaxUnavailable:
            return "MathJax 不可用：请确认 scriptURL 指向 SVG 发行版（tex-mml-svg.js），且网络可达"
        case .invalidLatex(let message):
            return "LaTeX 语法错误：\(message)"
        case .timeout:
            return "公式排版超时"
        case .webViewFailed(let error):
            return "WebView 加载失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - MathJaxWebView

/// 离屏 MathJax 排版器。
///
/// 内部是一个**不加入视图层级**的 `WKWebView`，只用来跑 MathJax 的排版算法。
/// 全 App 共用 `shared` 即可，不要为每条公式新建实例。
public final class MathJaxWebView: NSObject {

    // MARK: 单例

    /// 共享实例。绝大多数场景直接用它。
    public static let shared = MathJaxWebView()

    // MARK: 配置

    /// 排版参数。修改后仅影响**之后**的请求；已缓存的结果不会失效，
    /// 需要一并刷新时请调用 `clearCache()`。
    public var options = MathRenderOptions()

    /// SVG → UIImage 的解码器。
    ///
    /// 默认实现会在能 `import SDWebImageSVGCoder` 时走它；否则返回 `nil`
    /// （此时 `MathRenderOutput.svg` 仍然可用，只是没有 `image`）。
    /// 想换成 SVGKit、Macaw 或自研解码器，替换这个闭包即可：
    ///
    /// ```swift
    /// MathJaxWebView.shared.svgDecoder = { svg, size, scale in
    ///     MySVGEngine.render(svg, size: size, scale: scale)
    /// }
    /// ```
    public var svgDecoder: (_ svg: String, _ size: CGSize, _ scale: CGFloat) -> UIImage? = {
        MathJaxWebView.defaultSVGDecoder($0, $1, $2)
    }

    // MARK: 私有状态

    /// 排版用的隐藏 WebView。
    ///
    /// 给一个非零 frame 是**必需**的：JS 侧要靠 `getBoundingClientRect()`
    /// 量出公式的真实像素尺寸，零尺寸的 WebView 不会触发布局，量出来全是 0。
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(MessageProxy(owner: self), name: Self.messageName)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024),
                            configuration: configuration)
        web.navigationDelegate = self
        web.isHidden = true
        web.isUserInteractionEnabled = false
        return web
    }()

    private static let messageName = "mathjax"

    /// WebView / MathJax 的加载状态。
    private enum ReadyState {
        case idle       // 还没开始加载
        case loading    // HTML 已注入，等 MathJax 的 startup.promise
        case ready      // 可以排版了
        case failed(MathRenderError)
    }

    private var state: ReadyState = .idle

    /// 等待 MathJax 就绪期间堆积的请求。
    private var pendingTasks: [RenderTask] = []

    /// 已发给 JS、等待回调的请求，key 为请求 id。
    private var inflightTasks: [Int: RenderTask] = [:]

    private var nextRequestID = 0

    /// 结果缓存。key 由 latex + 所有影响外观的参数组合而成。
    private let cache = NSCache<NSString, CachedOutput>()

    private final class CachedOutput {
        let output: MathRenderOutput
        init(_ output: MathRenderOutput) { self.output = output }
    }

    private struct RenderTask {
        let id: Int
        let formula: MathFormula
        let options: MathRenderOptions
        let cacheKey: String
        let completion: (Result<MathRenderOutput, MathRenderError>) -> Void
        var timeoutWorkItem: DispatchWorkItem?
    }

    private override init() {
        super.init()
        cache.countLimit = 200
    }

    // MARK: - 公开 API

    /// 排版一条公式，拿到 SVG + 尺寸 + 基线 + 图片。
    ///
    /// - Parameters:
    ///   - latex: LaTeX 源码，不要带 `$` / `$$` 定界符。
    ///   - displayMode: `true` 块级，`false` 行内。
    ///   - options: 覆盖本次请求的排版参数；传 `nil` 用全局 `options`。
    ///   - completion: 主线程回调。
    public func render(_ latex: String,
                       displayMode: Bool,
                       options: MathRenderOptions? = nil,
                       completion: @escaping (Result<MathRenderOutput, MathRenderError>) -> Void) {
        render(MathFormula(latex: latex, isDisplayMode: displayMode),
               options: options,
               completion: completion)
    }

    /// 排版一条公式。
    public func render(_ formula: MathFormula,
                       options overrides: MathRenderOptions? = nil,
                       completion: @escaping (Result<MathRenderOutput, MathRenderError>) -> Void) {
        // WKWebView 只能在主线程操作，统一切过去，调用方不用关心线程。
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.render(formula, options: overrides, completion: completion)
            }
            return
        }

        let options = overrides ?? self.options
        let latex = formula.latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty else {
            completion(.failure(.emptyFormula))
            return
        }

        let key = cacheKey(for: formula, options: options)
        if let cached = cache.object(forKey: key as NSString) {
            completion(.success(cached.output))
            return
        }

        nextRequestID += 1
        let requestID = nextRequestID

        // 超时兜底：CDN 不可达时 JS 侧不会有任何回调，必须由原生侧收口，
        // 否则 completion 永远不触发，调用方的 loading 会一直转。
        //
        // 只捕获 requestID 而不是整个 task：task 持有 timeoutWorkItem，
        // 捕获 task 会形成 workItem → task → workItem 的循环引用。
        let timeoutItem = DispatchWorkItem { [weak self] in
            self?.finish(requestID: requestID, with: .failure(.timeout))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + options.timeout, execute: timeoutItem)

        let task = RenderTask(id: requestID,
                              formula: MathFormula(latex: latex, isDisplayMode: formula.isDisplayMode),
                              options: options,
                              cacheKey: key,
                              completion: completion,
                              timeoutWorkItem: timeoutItem)

        switch state {
        case .ready:
            dispatchToJS(task)
        case .loading:
            pendingTasks.append(task)
        case .idle:
            pendingTasks.append(task)
            bootstrap(with: options)
        case .failed:
            // 失败后再来请求，给一次重新加载的机会（可能是网络已经恢复）。
            pendingTasks.append(task)
            state = .idle
            bootstrap(with: options)
        }
    }

    /// 便捷方法：只要图片。
    public func renderImage(_ latex: String,
                            displayMode: Bool,
                            options: MathRenderOptions? = nil,
                            completion: @escaping (Result<UIImage, MathRenderError>) -> Void) {
        render(latex, displayMode: displayMode, options: options) { result in
            switch result {
            case .success(let output):
                if let image = output.image {
                    completion(.success(image))
                } else {
                    completion(.failure(.mathJaxUnavailable))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// 批量排版。全部完成（无论成功失败）后回调一次。
    ///
    /// - Parameter completion: 结果数组与入参 `formulas` **一一对应、顺序一致**。
    public func render(_ formulas: [MathFormula],
                       options: MathRenderOptions? = nil,
                       completion: @escaping ([Result<MathRenderOutput, MathRenderError>]) -> Void) {
        guard !formulas.isEmpty else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        var results = [Result<MathRenderOutput, MathRenderError>?](repeating: nil,
                                                                   count: formulas.count)
        let group = DispatchGroup()

        for (index, formula) in formulas.enumerated() {
            group.enter()
            render(formula, options: options) { result in
                results[index] = result
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(results.map { $0 ?? .failure(.timeout) })
        }
    }

    /// 提前加载 MathJax。
    ///
    /// 首次排版要等脚本下载 + 初始化（CDN 冷启动约 0.5~2s）。
    /// 在进入聊天页 / 文档页时调一次，用户真正看到公式时就是秒出。
    public func prewarm() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.prewarm() }
            return
        }
        if case .idle = state {
            bootstrap(with: options)
        }
    }

    /// 清空缓存。切换深色模式或正文字号后调用。
    public func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - 内部：启动

    private func bootstrap(with options: MathRenderOptions) {
        state = .loading
        // baseURL 指向 Bundle，本地放了 tex-mml-svg.js 时才能用相对路径加载到。
        let baseURL = Bundle.main.resourceURL
        webView.loadHTMLString(makeHTML(with: options), baseURL: baseURL)
    }

    /// 本地优先：Target 里放了 `tex-mml-svg.js` 就用本地，否则回落到 CDN。
    private func resolvedScriptTag(for options: MathRenderOptions) -> String {
        if Bundle.main.path(forResource: "tex-mml-svg", ofType: "js") != nil {
            return #"<script id="MathJax-script" src="tex-mml-svg.js"></script>"#
        }
        return #"<script id="MathJax-script" src="\#(options.scriptURL)"></script>"#
    }

    private func makeHTML(with options: MathRenderOptions) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            /* 排版容器不可见但必须参与布局，否则 getBoundingClientRect 全是 0 */
            body { margin: 0; padding: 0; }
            #stage {
              position: absolute;
              top: 0; left: 0;
              visibility: hidden;
              white-space: nowrap;
            }
          </style>
          <script>
            window.MathJax = {
              loader: { load: ['input/tex', 'output/svg'] },
              tex: {
                packages: { '[+]': ['ams', 'color', 'boldsymbol', 'mhchem'] },
                // 关掉自动扫描：本类是「按需单条排版」，不需要 MathJax 去遍历页面
                inlineMath: [],
                displayMath: []
              },
              svg: {
                // ⚠️ 必须是 'local'。
                //
                // 默认的 'global' 会把字形的 <path> 定义集中放在 <body> 末尾的一个
                // 共享 <svg> 里，各公式通过 <use xlink:href="#MJX-..."> 引用。
                // 我们只会把单条公式的 <svg> 抠出来交给原生，一旦脱离页面，
                // 这些外部引用就全部失效 —— 表现为「有尺寸但画面全白」。
                // 'local' 让每条公式自带 <defs>，产物自包含。
                fontCache: 'local'
              },
              startup: {
                typeset: false,
                pageReady: function () {
                  return MathJax.startup.defaultPageReady().then(function () {
                    window.__mathjaxReady = true;
                    post({ type: 'ready' });
                  });
                }
              }
            };

            function post(payload) {
              try {
                window.webkit.messageHandlers.\(Self.messageName).postMessage(payload);
              } catch (e) {}
            }

            /**
             * 排版单条公式。
             * @param {number} id        请求 id，用于回调配对
             * @param {string} tex       LaTeX 源码
             * @param {boolean} display  是否块级
             * @param {string} color     颜色（#RRGGBB 或 rgba(...)）
             * @param {number} fontSize  基准字号（px）
             */
            function mdTypeset(id, tex, display, color, fontSize) {
              if (!window.__mathjaxReady || !window.MathJax || typeof MathJax.tex2svg !== 'function') {
                post({ type: 'result', id: id, error: 'unavailable' });
                return;
              }
              var stage = document.getElementById('stage');
              try {
                var wrapper = MathJax.tex2svg(tex, { display: display });
                var svg = wrapper.querySelector('svg');
                if (!svg) {
                  post({ type: 'result', id: id, error: 'MathJax 未产出 SVG' });
                  return;
                }

                // MathJax 把语法错误渲染成红色的 <merror> 节点，而不是抛异常，
                // 必须显式检测，否则原生侧会拿到一张「写着报错信息的图片」。
                var err = wrapper.querySelector('[data-mjx-error]');
                if (err) {
                  post({ type: 'result', id: id,
                         error: err.getAttribute('data-mjx-error') || 'LaTeX 语法错误' });
                  return;
                }

                // ── 量尺寸 ──
                // MathJax 输出的 width/height 单位是 ex（相对字号），
                // 原生 SVG 解码器基本都不认，必须换算成 px。
                // 做法：把节点真正放进文档量一次 getBoundingClientRect。
                stage.innerHTML = '';
                stage.style.fontSize = fontSize + 'px';
                stage.appendChild(wrapper);

                var rect = svg.getBoundingClientRect();
                var widthPx = rect.width;
                var heightPx = rect.height;

                // ── 算基线 ──
                // MathJax 用 style="vertical-align: -1.234ex" 表达基线下沉量。
                // 换算成 px 后交给原生设 NSTextAttachment.bounds.origin.y。
                var heightEx = parseFloat(svg.getAttribute('height')) || 0;
                var valignEx = parseFloat((svg.style.verticalAlign || '0').replace('ex', '')) || 0;
                var pxPerEx = heightEx > 0 ? (heightPx / heightEx) : 0;
                var baseline = valignEx * pxPerEx;

                // ── 固化属性，让 SVG 脱离页面也能正确解码 ──
                svg.setAttribute('width', widthPx + 'px');
                svg.setAttribute('height', heightPx + 'px');
                if (!svg.getAttribute('xmlns')) {
                  svg.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
                }
                if (!svg.getAttribute('xmlns:xlink')) {
                  svg.setAttribute('xmlns:xlink', 'http://www.w3.org/1999/xlink');
                }
                svg.style.verticalAlign = '';

                var markup = new XMLSerializer().serializeToString(svg);
                // currentColor 依赖 CSS 继承，脱离页面后无法解析 → 替换成实际颜色
                markup = markup.split('currentColor').join(color);

                stage.innerHTML = '';

                post({
                  type: 'result',
                  id: id,
                  svg: markup,
                  width: widthPx,
                  height: heightPx,
                  baseline: baseline
                });
              } catch (e) {
                stage.innerHTML = '';
                post({ type: 'result', id: id, error: (e && e.message) ? e.message : String(e) });
              }
            }
          </script>
          \(resolvedScriptTag(for: options))
        </head>
        <body>
          <div id="stage"></div>
        </body>
        </html>
        """
    }

    // MARK: - 内部：派发与回收

    private func dispatchToJS(_ task: RenderTask) {
        inflightTasks[task.id] = task

        // 用 JSON 编码传参，而不是手工拼字符串。
        // LaTeX 里满是反斜杠（\frac、\sqrt），手工转义极易出错，
        // JSONSerialization 能一次性处理好引号、反斜杠和换行。
        let latexLiteral = jsStringLiteral(task.formula.latex)
        let colorLiteral = jsStringLiteral(task.options.textColor.mathjax_cssColor)
        let script = """
        mdTypeset(\(task.id), \(latexLiteral), \(task.formula.isDisplayMode), \
        \(colorLiteral), \(task.options.fontSize));
        """

        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let error = error else { return }
            self?.finish(requestID: task.id,
                         with: .failure(.invalidLatex(error.localizedDescription)))
        }
    }

    private func flushPendingTasks() {
        let tasks = pendingTasks
        pendingTasks.removeAll()
        tasks.forEach(dispatchToJS)
    }

    private func failAllTasks(_ error: MathRenderError) {
        let pending = pendingTasks
        let inflight = Array(inflightTasks.values)
        pendingTasks.removeAll()
        inflightTasks.removeAll()
        for task in pending + inflight {
            task.timeoutWorkItem?.cancel()
            task.completion(.failure(error))
        }
    }

    private func finish(requestID: Int,
                        with result: Result<MathRenderOutput, MathRenderError>) {
        // inflight 里取不到说明已经被超时或其他路径收口过了，直接忽略，
        // 保证每个请求的 completion 有且只调用一次。
        guard let task = inflightTasks.removeValue(forKey: requestID) else { return }
        task.timeoutWorkItem?.cancel()

        if case .success(let output) = result {
            cache.setObject(CachedOutput(output), forKey: task.cacheKey as NSString)
        }
        task.completion(result)
    }

    // MARK: - 内部：JS 消息处理

    fileprivate func handle(message body: [String: Any]) {
        switch body["type"] as? String {
        case "ready":
            state = .ready
            flushPendingTasks()

        case "result":
            guard let id = body["id"] as? Int else { return }

            if let error = body["error"] as? String {
                let failure: MathRenderError = (error == "unavailable")
                    ? .mathJaxUnavailable
                    : .invalidLatex(error)
                finish(requestID: id, with: .failure(failure))
                return
            }

            guard let svg = body["svg"] as? String,
                  let width = body["width"] as? Double,
                  let height = body["height"] as? Double,
                  width > 0, height > 0 else {
                finish(requestID: id, with: .failure(.invalidLatex("排版结果尺寸无效")))
                return
            }

            let baseline = (body["baseline"] as? Double) ?? 0
            let size = CGSize(width: CGFloat(width), height: CGFloat(height))
            let scale = inflightTasks[id]?.options.scale ?? options.scale
            let image = svgDecoder(svg, size, scale)

            finish(requestID: id,
                   with: .success(MathRenderOutput(svg: svg,
                                                   size: size,
                                                   baselineOffset: CGFloat(baseline),
                                                   image: image)))
        default:
            break
        }
    }

    // MARK: - 工具

    private func cacheKey(for formula: MathFormula, options: MathRenderOptions) -> String {
        // 所有影响最终像素的参数都要进 key，否则换颜色 / 换字号会命中旧缓存。
        [
            formula.latex,
            formula.isDisplayMode ? "block" : "inline",
            options.textColor.mathjax_cssColor,
            String(format: "%.2f", options.fontSize),
            String(format: "%.2f", options.scale)
        ].joined(separator: "\u{1}")
    }

    private func jsStringLiteral(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string],
                                                     options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        // JSONSerialization 顶层必须是数组 / 字典，所以包一层再把方括号剥掉。
        return String(json.dropFirst().dropLast())
    }

    /// 默认 SVG 解码实现。
    private static func defaultSVGDecoder(_ svg: String,
                                          _ size: CGSize,
                                          _ scale: CGFloat) -> UIImage? {
        #if canImport(SDWebImageSVGCoder)
        guard let data = svg.data(using: .utf8) else { return nil }
        _ = SVGCoderRegistration.once
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let image = SDImageSVGCoder.shared.decodedImage(with: data, options: [
            .decodeThumbnailPixelSize: pixelSize,
            .decodePreserveAspectRatio: true
        ])
        guard let cgImage = image?.cgImage else { return image }
        // 按 scale 重建，保证 UIImage.size 回到逻辑点，排版时不会放大一倍。
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        #else
        return nil
        #endif
    }
}

// MARK: - WKNavigationDelegate

extension MathJaxWebView: WKNavigationDelegate {

    public func webView(_ webView: WKWebView,
                        didFail navigation: WKNavigation!,
                        withError error: Error) {
        state = .failed(.webViewFailed(error))
        failAllTasks(.webViewFailed(error))
    }

    public func webView(_ webView: WKWebView,
                        didFailProvisionalNavigation navigation: WKNavigation!,
                        withError error: Error) {
        state = .failed(.webViewFailed(error))
        failAllTasks(.webViewFailed(error))
    }
}

// MARK: - JS 消息代理

/// 独立的消息代理。
///
/// `WKUserContentController` 会**强引用** message handler，
/// 如果让 `MathJaxWebView` 自己实现 `WKScriptMessageHandler`，就会形成
/// `MathJaxWebView → webView → userContentController → MathJaxWebView` 的循环。
/// 单例场景下不致命，但业务方自建实例时会泄漏整个 WebView 进程。
private final class MessageProxy: NSObject, WKScriptMessageHandler {

    private weak var owner: MathJaxWebView?

    init(owner: MathJaxWebView) {
        self.owner = owner
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        owner?.handle(message: body)
    }
}

// MARK: - SVG 解码器注册

#if canImport(SDWebImageSVGCoder)
/// `SDImageSVGCoder` 必须显式注册才会生效。
/// 用 `static let` 保证全进程只注册一次且线程安全。
private enum SVGCoderRegistration {
    static let once: Void = {
        SDImageCodersManager.shared.addCoder(SDImageSVGCoder.shared)
    }()
}
#endif

// MARK: - 颜色转换

private extension UIColor {

    /// 转成 SVG / CSS 能识别的颜色字符串。
    ///
    /// 动态色（如 `.label`）必须先用 `resolvedColor(with:)` 解析成具体值，
    /// 否则在非主线程或无 trait 环境下拿到的分量是错的。
    var mathjax_cssColor: String {
        let resolved: UIColor
        if #available(iOS 13.0, *) {
            resolved = self.resolvedColor(with: UITraitCollection.current)
        } else {
            resolved = self
        }

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "#000000"
        }

        if a >= 1.0 {
            return String(format: "#%02X%02X%02X",
                          Int((r * 255).rounded()),
                          Int((g * 255).rounded()),
                          Int((b * 255).rounded()))
        }
        return String(format: "rgba(%d,%d,%d,%.3f)",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()),
                      a)
    }
}

// MARK: - NSTextAttachment 便捷扩展

public extension MathRenderOutput {

    /// 直接做成可插进 `NSAttributedString` 的附件。
    ///
    /// 已把 `baselineOffset` 写进 `bounds.origin.y`，所以行内公式能和
    /// 周围文字正确对齐（分数线、求和符号不会错位）：
    ///
    /// ```swift
    /// MathJaxWebView.shared.render("x^2", displayMode: false) { result in
    ///     guard let output = try? result.get() else { return }
    ///     let text = NSMutableAttributedString(string: "当 ")
    ///     text.append(NSAttributedString(attachment: output.makeAttachment()))
    ///     text.append(NSAttributedString(string: " 时成立"))
    ///     label.attributedText = text
    /// }
    /// ```
    ///
    /// - Parameter maxWidth: 可用宽度上限。公式原始宽度超过它时**等比缩小**
    ///   （宽高和基线一起按同一比例缩放，保证不变形、不错位）。
    ///
    ///   这个参数对块级公式尤其重要：矩阵、长积分式动辄几百点宽，
    ///   不限制的话 `NSTextAttachment` 会直接超出 `UITextView` 的文本容器，
    ///   表现为公式右半截被裁掉。传 `nil` 表示不限制。
    func makeAttachment(maxWidth: CGFloat? = nil) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        attachment.image = image

        var displaySize = size
        var displayBaseline = baselineOffset

        if let maxWidth = maxWidth, maxWidth > 0, size.width > maxWidth {
            let ratio = maxWidth / size.width
            displaySize = CGSize(width: maxWidth, height: size.height * ratio)
            // 基线必须同比例缩放，否则缩小后的公式会相对文字上浮或下沉。
            displayBaseline = baselineOffset * ratio
        }

        attachment.bounds = CGRect(x: 0,
                                   y: displayBaseline,
                                   width: displaySize.width,
                                   height: displaySize.height)
        return attachment
    }
}
