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

   

    /// 与 `makeHTML(from:)` 等价的入口，但会根据 `kind` **按需**注入相应的 CSS / JS，
    /// 未涉及的第三方资源完全不加载。适合调用方已经知道当前 markdown 片段的类型
    /// （由 fenceInfo 或 AttrKey 判断得到）时使用。
    public static func makeHTML(from markdown: String,
                                kind: ContentKind,
                                direction: MarkdownLayoutDirection = .automatic) -> String {
        guard !markdown.isEmpty else { return "" }

        // 1. markdown → html：内置轻量转换（识别围栏代码块 + 段落，并转义 HTML 实体）
        //    - 围栏代码块 ```lang ... ``` → <pre><code class="language-lang">…</code></pre>
        //    - 其余文本按空行分段包进 <p>，仅转义 & < >，从而保留数学公式里的 $$ 与反斜杠
        //    - .html：直接把原始 HTML 作为 body，不做任何转换
        let bodyHTML = (kind == .html) ? markdown : markdownToHTML(markdown)

        // 2. 按类型做定向 HTML 变换（只处理当前类型对应的代码块）
        var normalized = bodyHTML

        if kind == .mermaid {
            normalized = normalized.replacingOccurrences(
                of: #"<pre><code class="language-mermaid">([\s\S]*?)</code></pre>"#,
                with: #"<div class="mermaid">$1</div>"#,
                options: .regularExpression
            )
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
            if (window.mermaid) {
              mermaid.initialize({ startOnLoad: true, theme: 'default', securityLevel: 'loose' });
            }
            """
        case .echarts:
            headAssets = #"<script src="echarts.min.js"></script>"#
            bootScript = """
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
        //    - KaTeX：数学公式的运算符顺序与上下标位置是绝对的；
        //    - Mermaid / ECharts：SVG 画布有自己的坐标系，镜像会让图表左右颠倒。
        //    `unicode-bidi: isolate` 让这些元素自成一个双向隔离区，
        //    不把自己的方向「泄漏」给外层，也不被外层影响。
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
