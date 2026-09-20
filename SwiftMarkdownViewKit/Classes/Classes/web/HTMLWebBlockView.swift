//
//  HTMLWebBlockView.swift
//  SwiftMarkdownViewKit
//
//  复杂 / 带脚本 HTML 的 WebView 渲染视图（分级路由的最后一档）。
//  复用 BaseMarkdownWebBlockView 的高度自适应 + shimmer + 消息通道能力。
//

import UIKit
import Markdown

@available(iOS 13.0, *)
public final class HTMLWebBlockView: BaseMarkdownWebBlockView, ViewLoadable {

    public typealias MarkupType = HTMLBlock

    public func updateData(data: MarkupContext<HTMLBlock>) {
        load(data)
    }

    public func startStreaming(data: MarkupContext<HTMLBlock>, animation: Bool) {
        load(data)
    }

    public func estimatedSize(for data: MarkupContext<HTMLBlock>) -> CGSize {
        viewOptions.estimedSize ?? .zero
    }

    private func load(_ data: MarkupContext<HTMLBlock>) {
        let raw = data.markup.rawHTML
        // 未闭合（如 <body> 已到但 </body> 还没到）→ isClosed=false，
        // BaseMarkdownWebBlockView.loadMarkdown 会加载 placeholder 并显示光晕，
        // 等标签闭合后再加载真正的 HTML。
        let closed = data.markup.isClosed(source: data.visitor.text)
        webBlockMatch = WebBlockMatch(title: "html",
                                      content: raw,
                                      isClosed: closed,
                                      direction: data.visitor.theme.layoutDirection)
        loadMarkdown(raw, htmlKind: .html)
    }
}
