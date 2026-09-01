//
//  File.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/9/1.
//

import Foundation
import Down
public struct Html {
   public static func makeHTML(from markdown: String) -> String {
        guard !markdown.isEmpty else { return "" }
        let mutable = markdown
        // 2. Down 转换剩余 markdown
        let down = Down(markdownString: mutable)
        var bodyHTML: String
        do {
            bodyHTML = try down.toHTML()
        } catch {
            bodyHTML = mutable
        }
        // 4. mermaid: <pre><code class="language-mermaid">…</code></pre> → <div class="mermaid">…</div>
        var normalized = bodyHTML.replacingOccurrences(
            of: #"<pre><code class="language-mermaid">([\s\S]*?)</code></pre>"#,
            with: #"<div class="mermaid">$1</div>"#,
            options: .regularExpression
        )

        // 5. echarts: <pre><code class="language-echarts">{JSON}</code></pre> → <div class="echarts" data-option="...">
        if let regex = try? NSRegularExpression(
            pattern: #"<pre><code class="language-echarts">([\s\S]*?)</code></pre>"#
        ) {
            let ns2 = normalized as NSString
            let ms = regex.matches(in: normalized, range: NSRange(location: 0, length: ns2.length))
            for m in ms.reversed() {
                let raw = ns2.substring(with: m.range(at: 1))
                let decoded = raw
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&#39;", with: "'")
                let attr = decoded.replacingOccurrences(of: "\"", with: "&quot;")
                let replacement = #"<div class="echarts" data-option="\#(attr)" style="width:100%;height:360px;margin:12px 0;"></div>"#
                normalized = (normalized as NSString).replacingCharacters(in: m.range, with: replacement)
            }
        }

        // 6. 组装 HTML: 本地 JS + KaTeX(优先本地, 缺失走 CDN)
        let katexAvailableLocally = Bundle.main.path(forResource: "katex.min", ofType: "js") != nil
        let katexCSS = katexAvailableLocally
            ? #"<link rel="stylesheet" href="katex.min.css">"#
            : #"<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">"#
        let katexJS = katexAvailableLocally
            ? #"<script src="katex.min.js"></script><script src="auto-render.min.js"></script>"#
            : #"<script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script><script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"></script>"#

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          \(katexCSS)
          <style>
            body { font-family: -apple-system, sans-serif; padding: 16px; font-size: 15px; color:#222; }
            pre  { background:#f6f8fa; padding:12px; border-radius:6px; overflow:auto; }
            code { font-family: Menlo, monospace; }
            .mermaid { text-align:center; margin: 12px 0; }
            table { border-collapse: collapse; margin: 12px 0; width: 100%; }
            th, td { border: 1px solid #ddd; padding: 6px 10px; }
            th { background: #f0f0f0; }
            .katex-display { overflow-x:auto; overflow-y:hidden; padding: 4px 0; }
          </style>
          <script src="mermaid.min.js"></script>
          <script src="echarts.min.js"></script>
          \(katexJS)
        </head>
        <body>
          \(normalized)
          <script>
            // mermaid
            if (window.mermaid) {
              mermaid.initialize({ startOnLoad: true, theme: 'default', securityLevel: 'loose' });
            }
            // echarts
            function renderECharts() {
              if (!window.echarts) return;
              document.querySelectorAll('.echarts').forEach(function(el) {
                var raw = el.getAttribute('data-option') || '';
                if (!raw) return;
                try {
                  var option = JSON.parse(raw);
                  var chart = echarts.init(el);
                  chart.setOption(option);
                  window.addEventListener('resize', function() { chart.resize(); });
                } catch (e) {
                  el.innerText = 'ECharts JSON 解析失败: ' + e.message;
                }
              });
            }
            // KaTeX: 扫描 DOM 里的 $...$ / $$...$$ / \\(...\\) / \\[...\\]
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
            function boot() { renderECharts(); renderMath(); }
            if (document.readyState === 'complete') { boot(); }
            else { window.addEventListener('load', boot); }
          </script>
        </body>
        </html>
        """
        return html
    }
}
