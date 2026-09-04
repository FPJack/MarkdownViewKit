//
//  File.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/9/4.
//

import Foundation
public class MarkdownLatexWebView: MarkdownWebBlockView {
    public override class var regex: String {
        RegxParser.latexBlockPattern
    }
}
