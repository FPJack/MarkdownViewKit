//
//  HtmlDirectiveRenderer.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/17.
//

import UIKit
import WebKit
import Markdown
public protocol HtmlDirectiveRenderer {
    func renderAttr(markup: HTMLBlock, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString?
    
    func renderView(markup: HTMLBlock, visitor: MarkdownAttributedStringBuilder) -> ViewLoadable?

    func render(markup: HTMLBlock,
                visitor: MarkdownAttributedStringBuilder) -> NSAttributedString?
}
public extension HtmlDirectiveRenderer {
    func renderAttr(markup: HTMLBlock, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString?{
        nil
    }
    
    func renderView(markup: HTMLBlock, visitor: MarkdownAttributedStringBuilder) -> ViewLoadable? {
        nil
    }

    public func render(markup: HTMLBlock,
                       visitor: MarkdownAttributedStringBuilder) -> NSAttributedString? {
        if let attr = renderAttr(markup: markup, visitor: visitor) {
            return attr
        } else if let view = renderView(markup: markup, visitor: visitor) {
            let attachment = BaseAttachment(markup: MarkupContext(markup: markup, visitor: visitor), viewBlock: {
                let view = renderView(markup: markup, visitor: visitor) ?? PlaceholdView()
                return view
            })
            let attributed = NSAttributedString(attachment: attachment)
            return attributed
        }
        return nil
    }
}

public struct HtmlRenderer: HtmlDirectiveRenderer {
    public func render(markup: HTMLBlock, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString? {
        if let attr = renderAttr(markup: markup, visitor: visitor) {
            return attr
        } else if let view = renderView(markup: markup, visitor: visitor) {
            let attachment = BaseAttachment(markup: MarkupContext(markup: markup, visitor: visitor), viewBlock: {
                let view = renderView(markup: markup, visitor: visitor) ?? PlaceholdView()
                return view
            })
            let attributed = NSAttributedString(attachment: attachment)
            return attributed
        }
        return nil
    }
    
    public func renderAttr(markup: HTMLBlock, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString? {
        HTMLRouter.renderBlock(markup, visitor: visitor)
    }
}
