//
//  File.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/9/1.
//

import Foundation
public struct Html {
    /// Web 内容类型。根据类型只加载相对应的 CSS / JS，减少 WKWebView 启动/渲染开销。
    public enum ContentKind {
        /// 流程图 / 时序图 / 甘特图等（mermaid）。
        case mermaid
        /// 图表（echarts）。
        case echarts
        /// 数学公式（KaTeX：$...$ / $$...$$ / \(...\) / \[...\]）。
        case latex
        /// 其他：不加载 mermaid / echarts / KaTeX 任何第三方资源，仅做基础 markdown → html。
        case code
        /// 原始 HTML：直接把内容作为 body 注入，不做 markdown 转换、不加载第三方资源。
        case html
        
    }

   

    /// 把 Mermaid 流程图的「布局方向」从左到右改成从右到左（`LR` → `RL`）。
    ///
    /// ## 为什么要单独做，而且默认关闭
    ///
    /// `graph LR` 里的 `LR` 是**作者在内容里写死的指令**，不是语言环境，
    /// 跟 `<div dir>` 完全是两回事——Mermaid 自己没有任何 RTL / 本地化概念。
    /// 所以这属于「改写用户内容」，必须由业务方显式开启，不能默认代劳。
    ///
    /// ## 为什么这样做是安全的
    ///
    /// 箭头的语义在 `A --> B`（A 指向 B）里，由**节点顺序**承载，
    /// `LR` / `RL` 只决定画布的排布方向。改成 `RL` 后箭头依旧是 A→B，
    /// 只是整张图的流向变成从右往左，符合阿拉伯语读者的阅读习惯。
    ///
    /// 这比给 SVG 加 `transform: scaleX(-1)` 正确得多——那种做法会把
    /// 节点里的文字一起镜像成反字。
    ///
    /// ## 不处理的情况
    ///
    /// `TB` / `TD` / `BT`（纵向流程图）保持原样：纵向流向与阅读方向无关，
    /// Mermaid 也不支持纵向图的分支左右镜像。
    ///
    /// - Parameter source: **图表源码本身**（尚未包进 `<div class="mermaid">` 的内容）。
    ///   传入已经包好标签的 HTML 会导致 `^` 匹配不到方向声明行。
    private static func mirroringDiagramFlow(_ source: String) -> String {
        // 只改「图表类型声明行」开头的方向 token，不碰节点 ID / 标签文字。
        source.replacingOccurrences(
            of: #"(?m)^(\s*(?:graph|flowchart)\s+)LR\b"#,
            with: "$1RL",
            options: [.regularExpression, .caseInsensitive]
        )
    }


    /// 未涉及的第三方资源完全不加载。适合调用方已经知道当前 markdown 片段的类型
    /// （由 fenceInfo 或 AttrKey 判断得到）时使用。
    /// - Parameter mirrorsDiagramFlow: RTL 下是否镜像图表的流向 / 坐标轴。
    ///
    ///   - Important: **故意不给默认值**。这个参数已经被漏传过两次
    ///     （Mermaid 一次、ECharts 一次），漏传的后果是配置开了却毫无效果，
    ///     而且不报错、只能靠肉眼看出来。去掉默认值让编译器强制每处显式传值。
    public static func makeHTML(from markdown: String,
                                kind: ContentKind,
                                direction: MarkdownLayoutDirection = .automatic,
                                mirrorsDiagramFlow: Bool) -> String {
        guard !markdown.isEmpty else { return "" }

        // 1. markdown → html：内置轻量转换（识别围栏代码块 + 段落，并转义 HTML 实体）
        //    - 围栏代码块 ```lang ... ``` → <pre><code class="language-lang">…</code></pre>
        //    - 其余文本按空行分段包进 <p>，仅转义 & < >，从而保留数学公式里的 $$ 与反斜杠
        //    - .html：直接把原始 HTML 作为 body，不做任何转换
        let bodyHTML = (kind == .html) ? markdown : markdownToHTML(markdown)

        // 2. 按类型做定向 HTML 变换（只处理当前类型对应的代码块）
        var normalized = bodyHTML

        if kind == .mermaid {
            // 注意：必须先把图表源码「捕获出来」再做方向改写，不能等包进
            // <div class="mermaid"> 之后再改——那时 `graph LR` 前面跟着开标签，
            // 已经不在行首，按行首匹配的正则会静默失配。
            if let regex = try? NSRegularExpression(
                pattern: #"<pre><code class="language-mermaid">([\s\S]*?)</code></pre>"#
            ) {
                let ns = normalized as NSString
                let matches = regex.matches(in: normalized,
                                            range: NSRange(location: 0, length: ns.length))
                // 倒序替换：保证前面未处理匹配的 range 不会因为长度变化而失效。
                for match in matches.reversed() {
                    var source = ns.substring(with: match.range(at: 1))
                    if mirrorsDiagramFlow, direction.isRightToLeft {
                        source = mirroringDiagramFlow(source)
                    }
                    normalized = (normalized as NSString).replacingCharacters(
                        in: match.range,
                        with: #"<div class="mermaid">"# + source + "</div>"
                    )
                }
            }
        }

        if kind == .echarts,
           let regex = try? NSRegularExpression(
            pattern: #"<pre><code class="language-echarts">([\s\S]*?)</code></pre>"#
           ) {
            let ns2 = normalized as NSString
            let ms = regex.matches(in: normalized, range: NSRange(location: 0, length: ns2.length))
            for m in ms.reversed() {
                let raw = ns2.substring(with: m.range(at: 1))
                let decoded = raw
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#34;",  with: "\"")
                    .replacingOccurrences(of: "&apos;", with: "'")
                    .replacingOccurrences(of: "&#39;",  with: "'")
                    .replacingOccurrences(of: "&lt;",   with: "<")
                    .replacingOccurrences(of: "&gt;",   with: ">")
                    .replacingOccurrences(of: "&amp;",  with: "&")
                    .replacingOccurrences(of: "\u{2028}", with: "\n")
                    .replacingOccurrences(of: "\u{2029}", with: "\n")
                let safeJSON = decoded.replacingOccurrences(of: "</", with: "<\\/")
                let replacement =
                    #"<div class="echarts" style="width:100%;height:360px;margin:12px 0;"></div>"# +
                    #"<script type="application/json" class="echarts-option">\#(safeJSON)</script>"#
                normalized = (normalized as NSString).replacingCharacters(in: m.range, with: replacement)
            }
        }

        // 3. 按需拼装外部依赖：只加载当前类型需要的 CSS / JS
        var headAssets = ""
        var bootScript = ""

        switch kind {
        case .mermaid:
            headAssets = #"<script src="mermaid.min.js"></script>"#
            bootScript = """
            // Mermaid 渲染出的是**尺寸写死的 SVG**，不会随容器宽度回流。
            // 横竖屏切换 / 分屏后必须重新渲染一次，否则图表会被裁切或留大片空白。
            //
            // 难点：mermaid 渲染完会把 <div class="mermaid"> 的文本内容替换成 SVG，
            // 原始图表源码就丢了，没法二次渲染。所以首次渲染前先把源码备份到
            // data-md-source 上。
            var MD_MERMAID_LAST_WIDTH = window.innerWidth;
            var MD_MERMAID_TIMER = null;
            var MD_MERMAID_RENDERING = false;
            var MD_MERMAID_PENDING = false;

            function mdBackupMermaidSource() {
              document.querySelectorAll('.mermaid').forEach(function (el) {
                if (el.hasAttribute('data-md-source')) return;
                // 已经被渲染成 SVG 的节点不能备份：此时 textContent 是
                // SVG 里的标签文字（"StartCheckYesDone..."），不是图表源码。
                if (el.querySelector('svg')) return;
                var src = el.textContent || '';
                if (!src.trim()) return;
                el.setAttribute('data-md-source', src);
              });
            }

            function mdRenderMermaid() {
              if (!window.mermaid) return;
              // 重入保护：mermaid.run 是异步的。
              // 若渲染途中又被触发（例如 WebView 尺寸变化引发 resize），
              // 会在上一次渲染还没结束时把 textContent 重置掉，
              // mermaid 读到半成品内容就会报 Syntax error。
              if (MD_MERMAID_RENDERING) { MD_MERMAID_PENDING = true; return; }

              var nodes = document.querySelectorAll('.mermaid');
              if (!nodes.length) return;

              var list = [];
              nodes.forEach(function (el) {
                var src = el.getAttribute('data-md-source');
                if (!src) return;
                // mermaid 用 data-processed 标记「已渲染」，不清掉就会跳过这个节点。
                el.removeAttribute('data-processed');
                el.textContent = src;
                list.push(el);
              });
              if (!list.length) return;

              MD_MERMAID_RENDERING = true;
              var done = function () {
                MD_MERMAID_RENDERING = false;
                if (MD_MERMAID_PENDING) {
                  MD_MERMAID_PENDING = false;
                  setTimeout(mdRenderMermaid, 0);
                }
              };
              try {
                var ret = (typeof mermaid.run === 'function')
                  ? mermaid.run({ nodes: list })          // mermaid v10+
                  : mermaid.init(undefined, list);        // mermaid v8 / v9
                if (ret && typeof ret.then === 'function') { ret.then(done, done); }
                else { done(); }
              } catch (e) { done(); }
            }

            // —— 下面这段必须**同步执行**，不能放进 window.load ——
            //
            // mermaid.min.js 自带 DOMContentLoaded 自动渲染（startOnLoad 默认 true）。
            // 而 bootScript 位于 </body> 之前、在文档解析过程中同步执行，
            // 是唯一能抢在自动渲染之前把它关掉并备份源码的时机。
            //
            // 一旦延后到 window.load，顺序就变成：
            //   DOMContentLoaded → mermaid 自动渲染，div 内容变成 SVG
            //   window.load      → 备份到的是 SVG 的文字标签，再拿去渲染
            //                      → 💣 Syntax error in text
            (function () {
              if (!window.mermaid) return;
              mermaid.initialize({ startOnLoad: false, theme: 'default', securityLevel: 'loose' });
              mdBackupMermaidSource();
            })();

            window.addEventListener('resize', function () {
              // 只在**宽度**真的变化时重渲染。
              //
              // 这一层判断是必需的防死循环措施：重渲染会改动 DOM →
              // ResizeObserver 上报新高度 → native 调整 WebView 高度 →
              // 再次触发 resize。若不限定宽度，就会无限循环。
              if (window.innerWidth === MD_MERMAID_LAST_WIDTH) return;
              MD_MERMAID_LAST_WIDTH = window.innerWidth;
              clearTimeout(MD_MERMAID_TIMER);
              MD_MERMAID_TIMER = setTimeout(mdRenderMermaid, 150);
            });

            // 渲染时机与 mermaid 原本的自动渲染保持一致（DOMContentLoaded）。
            if (document.readyState === 'loading') {
              document.addEventListener('DOMContentLoaded', mdRenderMermaid);
            } else {
              mdRenderMermaid();
            }
            """
        case .echarts:
            headAssets = #"<script src="echarts.min.js"></script>"#
            // ECharts 把图表画在 <canvas> 上，CSS 的 direction 完全影响不到图表内部，
            // 必须在 option 层面处理。这里分两档：
            //   1) UI 外框（标题 / 图例 / 提示框）——始终跟随 RTL 镜像，这属于界面元素；
            //   2) 坐标轴方向 —— 走 mirrorsDiagramFlow 开关，因为它改变的是数据呈现顺序，
            //      和 Mermaid 的 LR→RL 属于同一类「产品决策」。
            let chartIsRTL = direction.isRightToLeft
            let chartMirrorsAxes = chartIsRTL && mirrorsDiagramFlow
            bootScript = """
            var MD_RTL = \(chartIsRTL);
            var MD_MIRROR_AXES = \(chartMirrorsAxes);

            function mdMirrorSide(value) {
              if (value === 'left') return 'right';
              if (value === 'right') return 'left';
              return value;
            }

            // 把 title / legend 这类 UI 元素的水平位置左右对调。
            function mdMirrorChrome(option) {
              ['title', 'legend'].forEach(function (key) {
                var node = option[key];
                if (!node) return;
                (Array.isArray(node) ? node : [node]).forEach(function (item) {
                  if (!item || typeof item !== 'object') return;
                  var hasLeft = item.left !== undefined;
                  var hasRight = item.right !== undefined;
                  if (typeof item.left === 'string') item.left = mdMirrorSide(item.left);
                  if (typeof item.right === 'string') item.right = mdMirrorSide(item.right);
                  // 数值型偏移：left:20 的镜像是 right:20，必须换键而不是换值。
                  if (typeof item.left === 'number' && !hasRight) {
                    item.right = item.left; delete item.left;
                  } else if (typeof item.right === 'number' && !hasLeft) {
                    item.left = item.right; delete item.right;
                  }
                });
              });
              // 标题默认靠行首，RTL 下即右侧。
              if (option.title) {
                (Array.isArray(option.title) ? option.title : [option.title]).forEach(function (t) {
                  if (t && t.left === undefined && t.right === undefined) t.left = 'right';
                });
              }
              // 提示框是 DOM 元素，用 CSS 让阿拉伯文正确排版。
              option.tooltip = option.tooltip || {};
              var tips = Array.isArray(option.tooltip) ? option.tooltip : [option.tooltip];
              tips.forEach(function (tip) {
                if (!tip || typeof tip !== 'object') return;
                var css = tip.extraCssText || '';
                tip.extraCssText = css + ';direction:rtl;text-align:right;';
              });
            }

            // 坐标轴镜像：类目从右往左排，数值轴挪到右侧。
            function mdMirrorAxes(option) {
              if (option.xAxis) {
                (Array.isArray(option.xAxis) ? option.xAxis : [option.xAxis]).forEach(function (axis) {
                  if (axis && typeof axis === 'object' && axis.inverse === undefined) axis.inverse = true;
                });
              }
              if (option.yAxis) {
                (Array.isArray(option.yAxis) ? option.yAxis : [option.yAxis]).forEach(function (axis) {
                  if (axis && typeof axis === 'object' && axis.position === undefined) axis.position = 'right';
                });
              }
            }

            function renderECharts() {
              if (!window.echarts) return;
              document.querySelectorAll('.echarts').forEach(function(el) {
                var raw = '';
                var next = el.nextElementSibling;
                if (next && next.tagName === 'SCRIPT' &&
                    next.getAttribute('type') === 'application/json' &&
                    next.classList.contains('echarts-option')) {
                    raw = next.textContent || '';
                } else {
                    raw = el.getAttribute('data-option') || '';
                }
                if (!raw) return;
                try {
                  var option;
                  try { option = JSON.parse(raw); }
                  catch (err1) { option = (new Function('return (' + raw + ')'))(); }
                  if (MD_RTL) { mdMirrorChrome(option); }
                  if (MD_MIRROR_AXES) { mdMirrorAxes(option); }
                  var chart = echarts.init(el);
                  chart.setOption(option);
                  window.addEventListener('resize', function() { chart.resize(); });
                } catch (e) {
                  el.innerText = 'ECharts JSON 解析失败: ' + e.message;
                }
              });
            }
            if (document.readyState === 'complete') { renderECharts(); }
            else { window.addEventListener('load', renderECharts); }
            """
        case .latex:
            let katexAvailableLocally = Bundle.main.path(forResource: "katex.min", ofType: "js") != nil
            let katexCSS = katexAvailableLocally
                ? #"<link rel="stylesheet" href="katex.min.css">"#
                : #"<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">"#
            let katexJS = katexAvailableLocally
                ? #"<script src="katex.min.js"></script><script src="auto-render.min.js"></script>"#
                : #"<script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script><script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"></script>"#
            headAssets = katexCSS + katexJS
            bootScript = """
            function renderMath() {
              if (typeof renderMathInElement !== 'function') return;
              renderMathInElement(document.body, {
                delimiters: [
                  { left: '$$', right: '$$', display: true },
                  { left: '$',  right: '$',  display: false },
                  { left: '\\\\(', right: '\\\\)', display: false },
                  { left: '\\\\[', right: '\\\\]', display: true }
                ],
                throwOnError: false
              });
            }
            if (document.readyState === 'complete') { renderMath(); }
            else { window.addEventListener('load', renderMath); }
            """
        case .code:
            headAssets = ""
            bootScript = ""
        case .html:
            // 原始 HTML：不注入任何第三方资源，body 已是完整 HTML 片段。
            headAssets = ""
            bootScript = ""
        }

        // 4. 排版方向
        //
        //    body 跟随方向镜像；但代码 / 公式 / 图表**必须**保持从左到右：
        //    - <pre>/<code>：`if (a > b) {` 在 RTL 下会被双向算法重排成乱序；
        //    - KaTeX：见下方「为什么公式不镜像」；
        //    - Mermaid / ECharts：SVG 画布有自己的坐标系，镜像会让图表左右颠倒。
        //    `unicode-bidi: isolate` 让这些元素自成一个双向隔离区，
        //    不把自己的方向「泄漏」给外层，也不被外层影响。
        //
        //    ──────────────────────────────────────────────────────────
        //    为什么公式不镜像（这一条经常被误判成 bug，请勿「顺手修好」）
        //    ──────────────────────────────────────────────────────────
        //
        //    1) 数学记号不是自然语言，它的方向不由语言环境决定。
        //       和「数字在阿拉伯语里永远从左往右读」是同一条规则的延伸——
        //       Unicode 双向算法里数字属于 EN/AN 类，天然按 LTR 排列。
        //       正文写 12345，阿拉伯读者也是从左往右读这串数字。
        //
        //    2) 阿拉伯世界确实存在 RTL 数学记号（Mashriq 传统教材），
        //       但那**不是把布局左右翻转**，而是换一整套符号系统：
        //         · 镜像字形：∑ / ∫ 要换成镜像版（如 U+2A11 ⨑）、根号开口反向
        //         · 变量字母：改用 Arabic Mathematical Alphabetic Symbols
        //                     （U+1EE00–U+1EEFF）这一整个 Unicode 区块
        //         · 数字：改用阿拉伯-印度数字 ٠١٢٣٤٥٦٧٨٩
        //       这是字体与排版引擎层面的能力，CSS 的 direction 完全做不到。
        //
        //    3) 现代阿拉伯语数字出版与学术写作**本来就统一用 LTR 记号**，
        //       阿拉伯语维基百科的公式也是 LTR。RTL 数学属于传统教材的少数用法。
        //
        //    4) 最关键：KaTeX 不支持 RTL 数学排版（MathJax 也仅有实验性支持）。
        //       如果硬给 .katex 加 direction: rtl，双向算法会把 KaTeX 生成的
        //       span 序列重排，而字形本身并不会镜像——结果不是「RTL 公式」，
        //       而是运算符错位、上下标跑偏的**乱码**，比现在严重得多。
        //
        //    对比 Mermaid：`graph LR` 的 LR 只是**画布布局参数**，与符号本身无关，
        //    所以改成 RL 是安全的（见 mirroringDiagramFlow），因此那个才做成开关。
        //    公式的方向是**焊死在字形和记号体系里**的，没有等价的安全开关。
        let isRTL = direction.isRightToLeft
        let dirAttribute = isRTL ? "rtl" : "ltr"
        let langAttribute = isRTL ? "ar" : "en"

        let html = """
        <!doctype html>
        <html lang="\(langAttribute)" dir="\(dirAttribute)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport"
              content="width=device-width,
                       initial-scale=1.0,
                       maximum-scale=1.0,
                       minimum-scale=1.0,
                       user-scalable=no">
          <style>
            body {
              font-family: -apple-system, sans-serif;
              padding: 16px;
              font-size: 15px;
              color:#222;
              direction: \(dirAttribute);
              text-align: start;
            }

            /* —— 以下内容强制从左到右，不参与 RTL 镜像 —— */
            pre, pre code, code, .hljs,
            .katex, .katex-display, .katex *,
            .mermaid, .mermaid svg,
            .echarts, .echarts * {
              direction: ltr;
              unicode-bidi: isolate;
            }
            pre, pre code, code, .hljs {
              text-align: left;
            }
            /* —— 强制 LTR 区域结束 —— */

            pre  { background:#f6f8fa; padding:12px; border-radius:6px; overflow:auto; }
            code { font-family: Menlo, monospace; }
            .mermaid { text-align:center; margin: 12px 0; }
            /* 兜底：重新渲染完成前（约 150ms 去抖窗口内），
               先用 CSS 把 SVG 约束在容器内，避免瞬间被裁切。 */
            .mermaid svg { max-width: 100%; height: auto; }
            table { border-collapse: collapse; margin: 12px 0; width: 100%; }
            th, td { border: 1px solid #ddd; padding: 6px 10px; text-align: start; }
            th { background: #f0f0f0; }
            .katex-display { overflow-x:auto; overflow-y:hidden; padding: 4px 0; }
            /* 列表符号跟随方向：RTL 时项目符号在右侧 */
            ul, ol { padding-inline-start: 24px; padding-inline-end: 0; }
            blockquote {
              margin-inline-start: 0;
              padding-inline-start: 12px;
              border-inline-start: 3px solid #ddd;
              color: #666;
            }
          </style>
          \(headAssets)
        </head>
        <body>
          \(normalized)
          <script>
            \(bootScript)
          </script>
        </body>
        </html>
        """
        return html
    }

    // MARK: - Markdown → HTML（轻量内置转换）

    /// 只转义会破坏 HTML 结构的三个字符，保留 `$`、反斜杠等（数学公式需要）。
    private static func htmlEscape(_ s: String) -> String {
        return s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// 把 Markdown 文本转成基础 HTML。
    ///
    /// 仅实现当前 WebView 渲染所需的最小子集：
    /// 1. 围栏代码块（``` 或 ~~~）→ `<pre><code class="language-<info>">…</code></pre>`，
    ///    其中 info 会被小写化，便于后续按 `language-mermaid` / `language-echarts` 做正则替换；
    /// 2. 其余按空行分段，包进 `<p>…</p>`，只做最小 HTML 转义，
    ///    从而完整保留 `$$…$$` / `\(…\)` 等数学公式定界符供 KaTeX 识别。
    private static func markdownToHTML(_ markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var html = ""
        var paragraph: [String] = []

        func flushParagraph() {
            let text = paragraph
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph.removeAll()
            guard !text.isEmpty else { return }
            html += "<p>\(htmlEscape(text))</p>\n"
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 围栏代码块起始
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                let info = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1

                var codeLines: [String] = []
                while i < lines.count {
                    let l = lines[i]
                    if l.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        i += 1 // 跳过收尾定界行
                        break
                    }
                    codeLines.append(l)
                    i += 1
                }

                let code = htmlEscape(codeLines.joined(separator: "\n"))
                let cls = info.isEmpty ? "" : " class=\"language-\(info.lowercased())\""
                html += "<pre><code\(cls)>\(code)</code></pre>\n"
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
            i += 1
        }
        flushParagraph()

        return html
    }
}
