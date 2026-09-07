////
////  File.swift
////  MarkdownViewKit
////
////  Created by admin on 2026/9/4.
////
//
//import Foundation
import UIKit



public class MarkdownLatexWebView: MarkdownWebBlockView {
    public class override func regxRule() -> RegxRule {
        return RegxRule(pattern: RegxParser.latexBlockPattern, options: [.anchorsMatchLines])
    }
    public override func convertTextMatch(_ markdownView: MarkdownView,match: TextMatch) -> TextMatch{
        let codeBlockMatch = getCodeBlockMatch(match: match)
        guard let codeBlockMatch = codeBlockMatch else { return match }
        return match.copy(with: codeBlockMatch)
    }
    
    private func getCodeBlockMatch(match: TextMatch) -> CodeBlockMatch? {
        let ns = match.sourceText as NSString

        let rangs = RegxParser.regxLatex(str: ns as String)
        guard let m = match.match else { return nil }
        let overall    = m.range
        let bodyRange  = m.range(at: 1)
        let closeRange = m.range(at: 2)
        let content  = (bodyRange.location != NSNotFound && bodyRange.length > 0)
            ? ns.substring(with: bodyRange)
            : ""
        let isClosed = (closeRange.location != NSNotFound && closeRange.length > 0)
        return CodeBlockMatch(range: overall,
                              title: "latex",
                              content: content,
                              isClosed: isClosed)
    }
}
