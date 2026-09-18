//
//  EChartDirectiveRenderer.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/14.
//


import UIKit

struct EChartDirectiveRenderer: CodeBlockDirectiveRenderer {
    var language: String
    func renderView(codeBlockCtx: CodeBlockContext) -> (any ViewLoadable)? {
        let webView = MarkdownWebBlockView()
        return webView
    }
}

