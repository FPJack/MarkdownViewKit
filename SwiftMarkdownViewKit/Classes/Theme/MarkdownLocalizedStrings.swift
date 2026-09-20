//
//  MarkdownLocalizedStrings.swift
//  SwiftMarkdownViewKit
//
//  库内置 UI 文案的多语言默认值。
//
//  背景：代码块头部的「代码 / 复制 / 已复制」原本是硬编码中文，
//  在阿拉伯语（或任何非中文）环境下会显得很突兀。
//  这里按 App 的首选语言给出默认值，业务方仍可通过
//  `CodeBlockOption.copyTitle = "…"` 等属性随时覆盖。
//

import Foundation

/// 库内置 UI 文案。
public struct MarkdownLocalizedStrings {

    /// 代码块未识别出语言时，头部展示的默认标题。
    public var codeBlockTitle: String
    /// 复制按钮标题。
    public var copy: String
    /// 复制成功后的临时标题。
    public var copied: String

    public init(codeBlockTitle: String, copy: String, copied: String) {
        self.codeBlockTitle = codeBlockTitle
        self.copy = copy
        self.copied = copied
    }
}

public extension MarkdownLocalizedStrings {

    /// 按 App 当前首选语言解析出的一套文案。
    ///
    /// 目前内置阿拉伯语 / 中文 / 英文三套，其余语言回退到英文。
    /// 需要更多语言时，业务方直接给 `CodeBlockOption` 的对应属性赋值即可。
    static var current: MarkdownLocalizedStrings {
        forLanguageCode(Locale.preferredLanguages.first ?? "en")
    }

    /// 按语言代码解析文案（`"ar"` / `"ar-SA"` / `"zh-Hans"` 等都能识别）。
    static func forLanguageCode(_ identifier: String) -> MarkdownLocalizedStrings {
        let code = identifier.lowercased()
        if code.hasPrefix("ar") {
            return MarkdownLocalizedStrings(codeBlockTitle: "رمز",
                                            copy: "نسخ",
                                            copied: "تم النسخ")
        }
        if code.hasPrefix("he") || code.hasPrefix("iw") {
            return MarkdownLocalizedStrings(codeBlockTitle: "קוד",
                                            copy: "העתק",
                                            copied: "הועתק")
        }
        if code.hasPrefix("zh") {
            return MarkdownLocalizedStrings(codeBlockTitle: "代码",
                                            copy: "复制",
                                            copied: "已复制")
        }
        return MarkdownLocalizedStrings(codeBlockTitle: "Code",
                                        copy: "Copy",
                                        copied: "Copied")
    }
}
