//
//  WebViewVC.swift
//  MarkdownViewKit_Example
//
//  Created by admin on 2026/8/31.
//  Copyright © 2026 CocoaPods. All rights reserved.
//

import UIKit
import Foundation
import Down
import WebKit

import MarkdownViewKit
class WebViewVC: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
      
        let wkwebview = WKWebView(frame: self.view.bounds)
        self.view.addSubview(wkwebview)
        let arr = extractFlowchartTexts(language: nil)
         print(arr)
//        wkwebview.loadHTMLString(Html.makeHTML(from: readmeMarkdown()), baseURL: nil)
    }
    private func readmeMarkdown() -> String {
        
        if let path = Bundle.main.path(forResource: "html", ofType: "md"),
           let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty {
          
            return content
        }
      
        return "# Test.md 未找到"
    }

    /// 从 html.md 中提取所有 mermaid 流程图代码块的文字内容
    /// - Parameter language: 代码块语言标识，默认 "mermaid"；传 nil 则匹配所有围栏代码块
    /// - Returns: 每个匹配到的代码块内部文本（不含 ``` 围栏），按出现顺序返回
    func extractFlowchartTexts(language: String? = "mermaid") -> [String] {
        let markdown = readmeMarkdown()
        return Self.extractFencedCodeBlocks(from: markdown, language: language)
    }

    /// 通用：用正则从 Markdown 文本里提取指定语言的围栏代码块内容
    static func extractFencedCodeBlocks(from markdown: String, language: String?) -> [String] {
        // 匹配： ```lang\n ... \n```
        // - 起始 ``` 前允许行首空白
        // - 语言标识可选
        // - 内容非贪婪，跨行
        let langPattern: String
        if let language = language, !language.isEmpty {
            langPattern = NSRegularExpression.escapedPattern(for: language)
        } else {
            langPattern = "[A-Za-z0-9_+-]*"
        }
        let pattern = "(?m)^[ \\t]*```[ \\t]*(\(langPattern))[ \\t]*\\r?\\n([\\s\\S]*?)\\r?\\n[ \\t]*```[ \\t]*$"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let nsText = markdown as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var results: [String] = []
        regex.enumerateMatches(in: markdown, options: [], range: range) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 3 else { return }
            let contentRange = match.range(at: 2)
            guard contentRange.location != NSNotFound else { return }
            let content = nsText.substring(with: contentRange)
            results.append(content)
        }
        return results
    }

}
