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

enum MarkdownTableParser {

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
        #"(?:^[ \t]*\|.*\|[ \t]*(?:\r?\n|\u2028))(?:^[ \t]*\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*(?:\r?\n|\u2028))(?:^[ \t]*\|.*\|[ \t]*(?:\r?\n|\u2028)?)*"#
  
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
}

