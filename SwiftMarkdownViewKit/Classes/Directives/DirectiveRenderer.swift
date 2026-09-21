//
//  File.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/21.
//

import Foundation
import Markdown
/// 行内自定义规则：自带匹配逻辑，命中后把匹配片段渲染成你想展示的富文本。
public protocol DirectiveRenderer {
    
    associatedtype MarkupType: Markup

    func renderAttr(markup: MarkupType, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString?
    
    func renderView(markup: MarkupType, visitor: MarkdownAttributedStringBuilder) -> ViewLoadable?

    func render(markup: MarkupType,
                visitor: MarkdownAttributedStringBuilder) -> NSAttributedString?
}
public extension DirectiveRenderer {
    func renderAttr(markup: MarkupType, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString?{
        nil
    }
    
    func renderView(markup: MarkupType, visitor: MarkdownAttributedStringBuilder) -> ViewLoadable? {
        nil
    }

    public func render(markup: MarkupType,
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


public struct RendererAttrImpl<T: Markup>: DirectiveRenderer {
    public typealias MarkupType = T
    
    public let renderAttr: (MarkupType, MarkdownAttributedStringBuilder) -> NSAttributedString?
    
    
    init(renderAttr: @escaping (MarkupType, MarkdownAttributedStringBuilder) -> NSAttributedString?) {
        self.renderAttr = renderAttr
    }

    public func renderAttr(markup: T, visitor: MarkdownAttributedStringBuilder) -> NSAttributedString? {
        return renderAttr(markup, visitor)
    }
}

public struct RendererViewImpl<T: Markup>: DirectiveRenderer {
    public typealias MarkupType = T

    public let renderView: (MarkupType, MarkdownAttributedStringBuilder) -> ViewLoadable?
    
    public func renderView(markup: MarkupType, visitor: MarkdownAttributedStringBuilder) -> (any ViewLoadable)? {
        return renderView(markup, visitor)
    }
   
}
