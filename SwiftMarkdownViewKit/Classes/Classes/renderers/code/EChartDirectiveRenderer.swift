//
//  EChartDirectiveRenderer.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/14.
//


import UIKit
import Markdown
struct EChartDirectiveRenderer: CodeBlockDirectiveRenderer {
    var viewType: any ViewLoadable.Type {
        MarkdownWebBlockView.self
    }
    
    var language: String
    func renderView(context: MarkupContext<CodeBlock>) -> (any ViewLoadable)? {
        let webView = MarkdownWebBlockView()
        return webView
    }
}

