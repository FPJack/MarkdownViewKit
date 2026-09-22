//
//  HtmlDirectiveRenderer.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/17.
//

import UIKit
import WebKit
import Markdown
public protocol HtmlDirectiveRenderer: DirectiveRenderer {
    typealias MarkupType = HTMLBlock
}

public struct HtmlRenderer: HtmlDirectiveRenderer {
    public var viewType: any ViewLoadable.Type {
        HTMLWebBlockView.self
    }
    public func renderView(context: MarkupContext<HTMLBlock>) -> (any ViewLoadable)? {
        viewType.init()
    }
    public func renderAttr(context: MarkupContext<HTMLBlock>) -> NSAttributedString? {
        HTMLRouter.renderBlock(context.markup, visitor: context.visitor)
    }
}
