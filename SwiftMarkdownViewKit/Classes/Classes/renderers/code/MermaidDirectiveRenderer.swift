//
//  MermaidDirectiveRenderer.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/14.
//

import UIKit

struct MermaidDirectiveRenderer: CodeBlockDirectiveRenderer {
    var language: String
    func renderView(codeBlockCtx: CodeBlockContext) -> (any ViewLoadable)? {
        let webView = MarkdownWebBlockView()
        return webView
    }
}
