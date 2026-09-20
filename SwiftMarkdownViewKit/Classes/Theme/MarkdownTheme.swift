//
//  MarkdownTheme.swift
//  SwiftMarkdownViewKit
//
//  主题 = 样式配置。
//
//  样式体系已按 Down 的方式重构为：
//    `MarkdownStylerConfiguration`（字体集合 / 颜色集合 / 段落样式集合 / Options）
//        ↓
//    `MarkdownStyler`（DefaultMarkdownStyler，可继承覆写）
//        ↓
//    `MarkdownAttributedStringBuilder`（只负责遍历语法树）
//
//  为了不破坏既有调用，这里把 `MarkdownTheme` 保留为配置对象的别名，
//  旧的扁平写法（`theme.bodyFont`、`theme.lineSpacing` 等）依然可用，
//  实现见 `MarkdownStylerConfiguration` 的兼容扩展。
//

import UIKit

/// Markdown 渲染主题（即 `MarkdownStylerConfiguration`）。
///
/// 推荐的新写法（与 Down 一致）：
/// ```swift
/// var theme = MarkdownTheme()
/// theme.fonts = StaticMarkdownFontCollection(body: .systemFont(ofSize: 16))
/// theme.colors = StaticMarkdownColorCollection(body: .darkGray, link: .systemPink)
/// theme.paragraphStyles = StaticMarkdownParagraphStyleCollection(lineSpacing: 6, paragraphSpacing: 14)
/// theme.listItemOptions = MarkdownListItemOptions(nestedIndentation: 26)
///
/// markdownView.parser.theme = theme        // 会自动重建 styler
/// ```
///
/// 仍然支持的旧写法：
/// ```swift
/// var theme = MarkdownTheme.default
/// theme.bodyFont = .systemFont(ofSize: 16)
/// theme.textColor = .darkGray
/// theme.lineSpacing = 6
/// ```
public typealias MarkdownTheme = MarkdownStylerConfiguration
