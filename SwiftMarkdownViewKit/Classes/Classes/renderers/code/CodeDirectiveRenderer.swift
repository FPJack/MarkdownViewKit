//
//  CodeDirectiveRenderer.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/14.
//

import UIKit
import Markdown

public struct CodeDirective: CodeBlockDirectiveRenderer {
    public var language: String = ""
    public func renderView(codeBlockCtx: CodeBlockContext) -> (any ViewLoadable)? {
        let cb = CodeBlockView()
        var configuration = CodeBlockOption()
        configuration.allowsVerticalScroll = false
        configuration.allowsHorizontalScroll = false
        configuration.codeFont = UIFont(name: "Menlo", size: 15)
        ?? .systemFont(ofSize: 15)
        configuration.lineNumberFont = configuration.codeFont
        cb.clipsToBounds = true
        cb.layer.cornerRadius = configuration.cornerRadius
        cb.layer.borderWidth = 1
        cb.layer.borderColor = configuration.borderColor.cgColor
        cb.showsLineNumbers = configuration.showsLineNumbers
        cb.allowsHorizontalScroll = configuration.allowsHorizontalScroll
        cb.allowsVerticalScroll = configuration.allowsVerticalScroll
        cb.maxCellWidth = configuration.maxCellWidth
        cb.maxViewWidth = configuration.maxWidth
        cb.maxViewHeight = configuration.maxHeight
        cb.codeFont = configuration.codeFont
        cb.lineNumberFont = configuration.lineNumberFont
        cb.lineNumberColor = configuration.lineNumberColor
        cb.gutterBackgroundColor = configuration.gutterBackgroundColor
        cb.codeBackgroundColor = configuration.codeBackgroundColor
        // 头部：语言名（或默认文字）+ 右侧复制按钮。
        let header = CodeBlockHeaderView(title: language ?? "",
                                         config: configuration,
                                         onCopy: {
        })
        cb.headerView = header
        return cb
    }
}
