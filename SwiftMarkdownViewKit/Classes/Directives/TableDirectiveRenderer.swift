//
//  CodeBlockDirectiveRenderer 2.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/17.
//

import UIKit
import Markdown

/// 行内自定义规则：自带匹配逻辑，命中后把匹配片段渲染成你想展示的富文本。
public protocol TableDirectiveRenderer {

    func renderAttr(markup: Table, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString?
    
    func renderView(markup: Table, visitor: MarkdownAttributedStringBuilder) -> ViewLoadable?

    func render(markup: Table,
                visitor: MarkdownAttributedStringBuilder) -> NSAttributedString?
}
public extension TableDirectiveRenderer {
    func renderAttr(markup: Table, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString?{
        nil
    }
    
    func renderView(markup: Table, visitor: MarkdownAttributedStringBuilder) -> ViewLoadable? {
        nil
    }

    public func render(markup: Table,
                       visitor: MarkdownAttributedStringBuilder) -> NSAttributedString? {
        if let attr = renderAttr(markup: markup, visitor: visitor) {
            return attr
        } else if let view = renderView(markup: markup, visitor: visitor) {
            let attachment = BaseAttachment(markup: MarkupContext(markup: markup, visitor: visitor), viewBlock: {
                let view = renderView(markup: markup, visitor: visitor) ?? PlaceholdView()
                return view
            })
            let attributed = NSAttributedString(attachment: attachment)
            return attributed
        }
        return nil
    }
}
public struct TableRenderer: TableDirectiveRenderer {
    public func renderView(markup: Table, visitor: MarkdownAttributedStringBuilder) -> (any ViewLoadable)? {
        let grid = GridTableView()
        var config = GridTableOptions()
        grid.configuration = config
        return grid
    }
}
