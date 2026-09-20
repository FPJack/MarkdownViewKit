//
//  MarkdownLayoutDirection.swift
//  SwiftMarkdownViewKit
//
//  排版方向（LTR / RTL）。这是整个 RTL（阿拉伯语、希伯来语等）适配的地基：
//  配置层只保存一个语义化的枚举，具体要转成
//  `NSWritingDirection` / `NSTextAlignment` / `UISemanticContentAttribute`
//  时通过本文件的便捷属性解析，避免在各处散落 `isRTL ? ... : ...` 的判断。
//
//  用法：
//  ```swift
//  var configuration = MarkdownStylerConfiguration()
//  configuration.layoutDirection = .rightToLeft   // 或 .automatic 跟随系统语言
//  ```
//

import UIKit

/// Markdown 内容的排版方向。
public enum MarkdownLayoutDirection {

    /// 强制从左到右（中文 / 英文等）。
    case leftToRight

    /// 强制从右到左（阿拉伯语 / 希伯来语 / 波斯语 / 乌尔都语等）。
    case rightToLeft

    /// 跟随 App 当前的界面语言方向（默认值）。
    ///
    /// 对中文 / 英文 App 解析结果就是 `.leftToRight`，因此不会改变既有行为；
    /// 当 App 切到阿拉伯语（或 Xcode 的 Right-to-Left Pseudolanguage）时自动变成 `.rightToLeft`。
    case automatic
}

// MARK: - 解析

public extension MarkdownLayoutDirection {

    /// 把 `.automatic` 解析成确定的方向（`.leftToRight` 或 `.rightToLeft`）。
    var resolved: MarkdownLayoutDirection {
        switch self {
        case .leftToRight, .rightToLeft:
            return self
        case .automatic:
            return MarkdownLayoutDirection.systemIsRightToLeft ? .rightToLeft : .leftToRight
        }
    }

    /// 最终是否为从右到左排版。
    var isRightToLeft: Bool {
        if case .rightToLeft = resolved { return true }
        return false
    }

    /// 对应的 TextKit 书写方向。
    ///
    /// 设置到 `NSParagraphStyle.baseWritingDirection` 之后，
    /// `firstLineHeadIndent` / `headIndent` / `tailIndent` 会自动镜像到正确的一侧，
    /// `NSTextAlignment.natural` 也会跟随它解析成左 / 右对齐。
    var writingDirection: NSWritingDirection {
        isRightToLeft ? .rightToLeft : .leftToRight
    }

    /// 「行首」一侧的对齐方式（LTR = 左对齐，RTL = 右对齐）。
    var leadingAlignment: NSTextAlignment {
        isRightToLeft ? .right : .left
    }

    /// 「行尾」一侧的对齐方式（LTR = 右对齐，RTL = 左对齐）。
    var trailingAlignment: NSTextAlignment {
        isRightToLeft ? .left : .right
    }

    /// 把一个对齐值解析成「当前方向下真正该用的对齐值」。
    ///
    /// 之所以需要这一步：`NSTextAlignment.natural` 是按 **App 的本地化语言**解析的，
    /// 而不是按段落的 `baseWritingDirection`。在中文 / 英文 App 里展示阿拉伯语内容时，
    /// `.natural` 会被错误地解析成左对齐，折行后的末行会贴在左边。
    ///
    /// 处理规则：
    /// - `.natural` → 按当前方向换成 `.left` / `.right`；
    /// - `.left` / `.right` → 视为「想跟随方向」的写法，同样换成当前方向的行首侧；
    /// - `.center` / `.justified` → 与方向无关，原样保留。
    ///
    /// 需要真正强制某一侧时，请在 styler 里覆写对应的 `style(...)` 方法。
    func resolvedAlignment(_ alignment: NSTextAlignment) -> NSTextAlignment {
        switch alignment {
        case .natural, .left, .right:
            return leadingAlignment
        default:
            return alignment
        }
    }

    /// 对应的 UIKit 语义方向，可直接赋给 `view.semanticContentAttribute`。
    var semanticContentAttribute: UISemanticContentAttribute {
        isRightToLeft ? .forceRightToLeft : .forceLeftToRight
    }

    /// 对应的 UIKit 布局方向。
    var userInterfaceLayoutDirection: UIUserInterfaceLayoutDirection {
        isRightToLeft ? .rightToLeft : .leftToRight
    }
}

// MARK: - 系统方向探测

public extension MarkdownLayoutDirection {

    /// 当前 App 的界面语言是否为从右到左。
    ///
    /// 优先使用 UIKit 的界面方向（能正确响应 Xcode 的
    /// “Right-to-Left Pseudolanguage” 调试选项）；
    /// 非主线程时回退到根据首选语言判断，保证线程安全。
    static var systemIsRightToLeft: Bool {
        if Thread.isMainThread {
            return UIView.userInterfaceLayoutDirection(for: .unspecified) == .rightToLeft
        }
        guard let language = Locale.preferredLanguages.first else { return false }
        return Locale.characterDirection(forLanguage: language) == .rightToLeft
    }
}

// MARK: - 由内容推断方向

public extension MarkdownLayoutDirection {

    /// 根据文本里第一个「强方向字符」推断排版方向。
    ///
    /// 适用于「App 是中文界面，但要展示一段阿拉伯语内容」的场景：
    /// ```swift
    /// configuration.layoutDirection = MarkdownLayoutDirection.inferred(from: markdownText)
    /// ```
    /// - Parameter text: 要推断的文本。
    /// - Returns: 找到强 RTL 字符返回 `.rightToLeft`；找到强 LTR 字符返回 `.leftToRight`；
    ///            全是数字 / 标点等中性字符时返回 `.automatic`。
    static func inferred(from text: String) -> MarkdownLayoutDirection {
        for scalar in text.unicodeScalars {
            if isStrongRightToLeft(scalar) { return .rightToLeft }
            if isStrongLeftToRight(scalar) { return .leftToRight }
        }
        return .automatic
    }

    /// 是否为强从右到左字符（阿拉伯语 / 希伯来语 / 叙利亚语 / 它们的扩展区与表现形式区）。
    private static func isStrongRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x05FF,   // Hebrew
             0x0600...0x06FF,   // Arabic
             0x0700...0x074F,   // Syriac
             0x0750...0x077F,   // Arabic Supplement
             0x0780...0x07BF,   // Thaana
             0x08A0...0x08FF,   // Arabic Extended-A
             0xFB1D...0xFDFF,   // Hebrew / Arabic Presentation Forms-A
             0xFE70...0xFEFF:   // Arabic Presentation Forms-B
            return true
        default:
            return false
        }
    }

    /// 是否为强从左到右字符（拉丁 / 希腊 / 西里尔 / CJK / 假名 / 谚文）。
    private static func isStrongLeftToRight(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0041...0x005A,   // A-Z
             0x0061...0x007A,   // a-z
             0x00C0...0x024F,   // Latin Extended
             0x0370...0x03FF,   // Greek
             0x0400...0x04FF,   // Cyrillic
             0x3040...0x30FF,   // 假名
             0x3400...0x4DBF,   // CJK 扩展 A
             0x4E00...0x9FFF,   // CJK 统一表意文字
             0xAC00...0xD7AF:   // 谚文
            return true
        default:
            return false
        }
    }
}

// MARK: - 双向隔离

public extension String {

    /// 用 Unicode 隔离符包裹，避免这段文本参与外层的双向重排。
    ///
    /// 典型场景：阿拉伯语段落里夹杂英文代码 / URL / 版本号时，
    /// 结尾的括号、句点会被双向算法甩到行首。用隔离符包住即可固定。
    ///
    /// - Parameter direction: 隔离区内部的方向。`nil` 表示由内容自动判断（FSI）。
    func markdown_bidiIsolated(_ direction: MarkdownLayoutDirection? = nil) -> String {
        let opening: String
        switch direction?.resolved {
        case .leftToRight:  opening = "\u{2066}"    // LRI
        case .rightToLeft:  opening = "\u{2067}"    // RLI
        default:            opening = "\u{2068}"    // FSI（首个强字符决定方向）
        }
        return opening + self + "\u{2069}"          // PDI
    }
}
