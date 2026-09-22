//
//  CodeBlockDirectiveRenderer 2.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/17.
//

import UIKit
import Markdown
/// 行内自定义规则：自带匹配逻辑，命中后把匹配片段渲染成你想展示的富文本。
public protocol TableDirectiveRenderer: DirectiveRenderer {
     typealias MarkupType = Table
}

public struct TableRenderer: TableDirectiveRenderer {
    public func renderView(context: MarkupContext<Table>) -> (any ViewLoadable)? {
        let grid = GridTableView()
        var config = GridTableOptions()
        // 把 Markdown 的排版方向透传给表格：RTL 时列序镜像、文字右对齐。
        config.layoutDirection = context.visitor.theme.layoutDirection
        grid.configuration = config
        return grid
    }
}




