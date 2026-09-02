//
//  MarkdownTableParser.swift
//  StreamingTextView_Example
//
//  Created by admin on 2026/8/19.
//  Copyright © 2026 CocoaPods. All rights reserved.
//

import Foundation

/// 一段 Markdown 的解析结果：要么是普通文本，要么是可直接喂给 `GridTableView` 的表格数据。
/// - `text`：非表格内容，原样返回。
/// - `table`：表格内容，已转成 `GridTableView` 需要的 `[[GridCellModel]]`
///   （第 0 行为表头，其余为数据行；分隔行 `| --- |` 已被跳过）。
/// 单次围栏代码块匹配结果。
public struct CodeBlockMatch {
    /// 匹配到的整体区间（含开头 ``` 那一行及结尾 ``` 那一行；未闭合时到字符串末尾）。
    let range: NSRange
    /// 语言标识（```之后的 info 字符串，如 `swift`）；未提供时为空串。
    let language: String
    /// 代码正文（不含定界行）。
    var content: String
    /// 代码块是否已闭合（即是否遇到收尾的 ``` ）。
    let isClosed: Bool
    
    var hmtlKind: Html.ContentKind {
        switch language.lowercased() {
        case "mermaid":
                .mermaid
        case "latex":
                .latex
        case "echarts":
                .echarts
        default:
                .other
        }
    }
}
enum RegxParser {

    /// 匹配 GFM 竖线表格的正则。
    ///
    /// 结构（三部分，逐行匹配，`.anchorsMatchLines` 让 `^` 贴住每一行行首）：
    ///   1) 表头行：`^[ \t]*\|.*\|[ \t]*\r?\n`
    ///      —— 以可选空白 + `|` 开头、含 `|` 结尾的一整行。
    ///   2) 分隔行：`^[ \t]*\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*\r?\n`
    ///      —— 每个单元格形如 `:?-+:?`（`-+` 允许 1 个及以上短横，比 `-{3,}` 更宽松），
    ///         首尾 `|` 均可选，`(?:...)*` 允许 1 列或多列。
    ///   3) 数据行：`(?:^[ \t]*\|.*\|[ \t]*\r?\n?)*`
    ///      —— 0 行或多行「含 `|` 的行」。遇到空行（无 `|`）自动结束，
    ///         因此两张以空行分隔的表格会被分别匹配成两段。
    ///
    /// 注意：横向空白只用 `[ \t]`（不用 `\s`），避免 `\s` 把换行也吃掉、
    /// 导致贪婪 `.*` 跨行错配。
//    private static let tablePattern = #"(?:^[ \t]*\|.*\|[ \t]*\r?\n)(?:^[ \t]*\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*\r?\n)(?:^[ \t]*\|.*\|[ \t]*\r?\n?)*"#
    
    private static let tablePattern =
        #"(?:^[ \t]*\|.*\|[ \t]*(?:\r?\n|\u2028|\u2029))(?:^[ \t]*\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*(?:\r?\n|\u2028|\u2029))(?:^[ \t]*\|.*\|[ \t]*(?:\r?\n|\u2028|\u2029)?)*"#

    /// 匹配「块级数学公式」的正则：以 `$$` 起、以 `$$` 止，中间任意内容（含换行 / U+2028）。
    ///
    /// 例：
    /// ```
    /// $$
    /// E = mc^2
    /// $$
    /// ```
    ///
    /// - 使用惰性匹配 `[\s\S]*?` 避免多个块被贪婪吞并；
    /// - 不用 `\s`，改用 `[\s\S]` 是为了跨行匹配（`.` 默认不匹配换行）；
    /// - 结尾允许可选换行（LF / CRLF / U+2028）以便连带吃掉尾部换行、避免空行残留。
    /// 匹配「块级数学公式」的正则（`$$ ... $$`），同时兼容两种常见写法：
    ///
    ///   ① 块式（起止各占一行）：
    ///      ```
    ///      $$
    ///      E = mc^2
    ///      $$
    ///      ```
    ///   ② 紧凑式（同一行 `$$…$$`）：
    ///      ```
    ///      $$\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$
    ///      ```
    ///
    /// 同时兼容「未闭合」的流式场景（末尾 `\z` 兜底）。
    ///
    /// 分组约定（与 `codeBlockPattern` 保持相似的 group 结构）：
    ///   - group 1：公式正文（不含首尾 `$$`；紧凑式没有前后换行、块式带 body 中间换行）。
    ///   - group 2：结尾 `$$`。**只在已闭合时才捕获**，未闭合时为 nil / 空。
    ///
    /// 结构（`.anchorsMatchLines` 让 `^` 贴每一行行首）：
    ///   1) 起始：`^[ \t]* $$` + 可选行终止（块式的换行 / 紧凑式无换行）
    ///   2) 正文：`[\s\S]*?` 惰性
    ///   3) 结束：
    ///        - 已闭合：可选行终止 + `[ \t]* $$ [ \t]*` + 行终止 / EOF → 捕获 group 2
    ///        - 未闭合：`\z` → 让流式过程中"只有开头没有结尾"也能匹配到
    private static let latexBlockPattern =
        #"^[ \t]*\$\$[ \t]*(?:(?:\r?\n|\u2028|\u2029)[ \t]*)?([\s\S]*?)(?:[ \t]*(\$\$)[ \t]*(?:\r?\n|\u2028|\u2029|\z)|\z)"#

    /// 匹配「围栏代码块」的正则（GFM 反引号 ``` 形式），同时兼容「代码块还未闭合」的流式场景。
    ///
    /// 分组约定（对应 `CodeBlockMatch` 的字段）：
    ///   - group 1：语言（fence info），如 `swift` / `python`；无语言时为空串。
    ///   - group 2：代码正文（不含首尾定界行；末尾换行不包含）。
    ///   - group 3：结束定界符 ` ``` `。**只有代码块已闭合时才捕获到内容**，
    ///             未闭合（流式过程中还没输入结束标记）时 group 3 为 nil / 空。
    ///
    /// 结构（`.anchorsMatchLines` 让 `^` 贴每一行行首）：
    ///   1) 起始行：`^[ \t]* ``` <lang>?(?:\r?\n|\u2028)`
    ///   2) 代码正文：`[\s\S]*?`（惰性，避免吞掉多个代码块）
    ///   3) 结束定界：
    ///        - 已闭合：`(?:\r?\n|\u2028)[ \t]* ``` [ \t]*(?:\r?\n|\u2028|\z)` → 捕获 group 3
    ///        - 未闭合：`\z`（字符串末尾）→ 让流式过程中"只有开头没有结尾"也能匹配到
    private static let codeBlockPattern =
        #"^[ \t]*```([^\r\n\u2028\u2029]*)(?:\r?\n|\u2028|\u2029)([\s\S]*?)(?:(?:\r?\n|\u2028|\u2029)[ \t]*(```)[ \t]*(?:\r?\n|\u2028|\u2029|\z)|\z)"#

   
  
    /// 把表格文本解析成 `GridTableView` 需要的单元格模型二维数组。
    @available(iOS 13.0, *)
    static func gridRows(from tableString: String) -> [[GridCellModel]] {
        tableRows(from: tableString).map { row in
            row.map { GridCellModel(text: $0) }
        }
    }

    /// 把表格文本解析成二维字符串（第 0 行表头，其余为数据行，列数对齐到表头，跳过分隔行）。
    static func tableRows(from tableString: String) -> [[String]] {
        let lines = tableString
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.contains("|") }
        guard lines.count >= 2 else { return [] }

        let header = splitCells(lines[0])
        var rows: [[String]] = [header]
        let colCount = header.count
        // lines[1] 是分隔行，跳过；从 lines[2] 起是数据行。
        for k in 2..<lines.count {
            var cells = splitCells(lines[k])
            if cells.count < colCount {
                cells += Array(repeating: "", count: colCount - cells.count)
            } else if cells.count > colCount {
                cells = Array(cells.prefix(colCount))
            }
            rows.append(cells)
        }
        return rows
    }

    /// 是否为分隔行：去首尾 `|` 后每个单元格都形如 `:?-+:?`。
    static func isSeparatorLine(_ line: String) -> Bool {
        let cells = splitCells(line)
        guard !cells.isEmpty else { return false }
        for c in cells {
            let t = c.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return false }
            if t.range(of: "^:?-+:?$", options: .regularExpression) == nil { return false }
        }
        return true
    }

    /// 把一行拆成单元格：去掉首尾 `|` 后按 `|` 分割并 trim。
    static func splitCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
   
    static func regxTable(attributex: NSAttributedString) -> [AttrRange] {
        let pattern = tablePattern
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return []
        }
       
//        let nsString = (attributex.string as NSString).replacingOccurrences(of: "\u{2028}", with: "\n") as NSString
        let nsString = (attributex.string as NSString)

//        nstr = nsString
////            .replacingOccurrences(of: "\r\n", with: "\n")
////            .replacingOccurrences(of: "\r", with: "\n")
//            .replacingOccurrences(of: "\u{2028}", with: "\n")
////            .replacingOccurrences(of: "\u{2029}", with: "\n") //段落换行
      
        let matches = regex.matches(in: nsString as String, range: NSRange(location: 0, length: nsString.length))
        var result: [AttrRange] = []
        for match in matches {
            let range = match.range
            let tableText = nsString.substring(with: range)
            result.append(AttrRange.table(range, AttrValue(tableText)))
        }
        return result
    }

    /// 匹配富文本中所有「块级数学公式」（`$$ ... $$`），并复用 `CodeBlockMatch` 结构承载结果。
    /// - `language` 固定为 `"latex"`；
    /// - `content` 为公式正文（不含 `$$` 定界符）；
    /// - `isClosed` 表示是否已收到收尾 `$$`（流式过程中未闭合时为 false）。
    static func regxLatex(attributex: NSAttributedString) -> [CodeBlockMatch] {
        guard let regex = try? NSRegularExpression(pattern: latexBlockPattern,
                                                   options: [.anchorsMatchLines]) else {
            return []
        }
        let ns = attributex.string as NSString
        let matches = regex.matches(in: ns as String,
                                    range: NSRange(location: 0, length: ns.length))
        var results: [CodeBlockMatch] = []
        for m in matches {
            let overall    = m.range
            let bodyRange  = m.range(at: 1)
            let closeRange = m.range(at: 2)

            let content  = (bodyRange.location != NSNotFound && bodyRange.length > 0)
                ? ns.substring(with: bodyRange)
                : ""
            let isClosed = (closeRange.location != NSNotFound && closeRange.length > 0)

            results.append(CodeBlockMatch(range: overall,
                                          language: "latex",
                                          content: content,
                                          isClosed: isClosed))
        }
        return results
    }

    /// 匹配一段文本中所有「围栏代码块」（``` ... ```），支持流式：
    /// 若最后一块只有开头没收尾，也会作为一条 `isClosed = false` 的结果返回。
    ///
    /// - Parameter text: 待扫描的原始字符串（可以是 markdown 源文本，也可以是富文本 `.string`）。
    /// - Returns: 按出现顺序返回的所有代码块匹配结果。
    static func matchCodeBlocks(in text: String) -> [CodeBlockMatch] {
        guard let regex = try? NSRegularExpression(pattern: codeBlockPattern,
                                                   options: [.anchorsMatchLines]) else {
            return []
        }
        let ns = text as NSString
        let matches = regex.matches(in: text,
                                    range: NSRange(location: 0, length: ns.length))
        var results: [CodeBlockMatch] = []
        for m in matches {
            let overall = m.range
            let langRange   = m.range(at: 1)
            let bodyRange   = m.range(at: 2)
            let closeRange  = m.range(at: 3)

            let language = (langRange.location != NSNotFound && langRange.length > 0)
                ? ns.substring(with: langRange).trimmingCharacters(in: .whitespaces)
                : ""
            let content  = (bodyRange.location != NSNotFound && bodyRange.length > 0)
                ? ns.substring(with: bodyRange)
                : ""
            let isClosed = (closeRange.location != NSNotFound && closeRange.length > 0)

            results.append(CodeBlockMatch(range: overall,
                                          language: language,
                                          content: content,
                                          isClosed: isClosed))
        }
        return results
    }

    /// 便捷方法：直接从 `NSAttributedString` 里扫描代码块。
    static func matchCodeBlocks(attributex: NSAttributedString) -> [CodeBlockMatch] {
        return matchCodeBlocks(in: attributex.string)
    }

    /// 匹配 `[video:URL]` 语法（支持 `[video:URL]`、`[video: URL]`、`[video:URL|title]`）：
    /// - group 1：URL；
    /// - group 2：可选标题（`|` 后的部分）。
    private static let videoPattern =
        #"\[video:\s*([^\]\|\s]+)(?:\s*\|\s*([^\]]+))?\s*\]"#

    /// 一个 `[video:URL]` 的匹配结果。
    public struct VideoMatch {
        public let range: NSRange
        public let urlString: String
        public let title: String?
    }

    /// 匹配富文本中所有 `[video:URL]`。
    static func regxVideo(attributex: NSAttributedString) -> [VideoMatch] {
        guard let regex = try? NSRegularExpression(pattern: videoPattern) else { return [] }
        let ns = attributex.string as NSString
        let matches = regex.matches(in: ns as String,
                                    range: NSRange(location: 0, length: ns.length))
        return matches.map { m in
            let url = ns.substring(with: m.range(at: 1))
            let titleRange = m.range(at: 2)
            let title = (titleRange.location != NSNotFound && titleRange.length > 0)
                ? ns.substring(with: titleRange).trimmingCharacters(in: .whitespaces)
                : nil
            return VideoMatch(range: m.range, urlString: url, title: title)
        }
    }

    // MARK: - Music

    /// 匹配 `[music:URL]` / `[music: URL]` / `[music:URL|title]`。
    private static let musicPattern =
        #"\[music:\s*([^\]\|\s]+)(?:\s*\|\s*([^\]]+))?\s*\]"#

    /// 一个 `[music:URL]` 的匹配结果。
    public struct MusicMatch {
        public let range: NSRange
        public let urlString: String
        public let title: String?
    }

    /// 匹配富文本中所有 `[music:URL]`。
    static func regxMusic(attributex: NSAttributedString) -> [MusicMatch] {
        guard let regex = try? NSRegularExpression(pattern: musicPattern) else { return [] }
        let ns = attributex.string as NSString
        let matches = regex.matches(in: ns as String,
                                    range: NSRange(location: 0, length: ns.length))
        return matches.map { m in
            let url = ns.substring(with: m.range(at: 1))
            let titleRange = m.range(at: 2)
            let title = (titleRange.location != NSNotFound && titleRange.length > 0)
                ? ns.substring(with: titleRange).trimmingCharacters(in: .whitespaces)
                : nil
            return MusicMatch(range: m.range, urlString: url, title: title)
        }
    }

    /// 每一项都是 `.code(range, AttrValue(CodeBlockMatch))`。
    /// 消费方可以从 `AttrValue.value as? CodeBlockMatch` 直接拿到语言 / 正文 / 是否闭合。
    static func regxWeb(attributex: NSAttributedString) -> [AttrRange] {
        var code = attributex.string
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return matchCodeBlocks(in: code).map { m in
            AttrRange.web(m.range, AttrValue(m))
        }
    }
}

