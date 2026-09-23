//
//  ChatTableCell.swift
//  SwiftMarkdownViewKit_Example
//
//  Created by admin on 2026/9/23.
//  Copyright © 2026 CocoaPods. All rights reserved.
//

import UIKit
import SwiftMarkdownViewKit
import ZLFlexKit

class ChatTableCell: UITableViewCell {
    var message: ChatMessage {
        willSet {
            if newValue.id != message.id {
                markdownView.clearTextViewAttributes()
            }
            let oldMarkdown = message.markdown
            let newMarkdown = newValue.markdown
            if newMarkdown.count > oldMarkdown.count {
                let newText = String(newMarkdown.suffix(newMarkdown.count - oldMarkdown.count))
                markdownView.appendText(fromMarkdown: newText)
            }
        }
    }
    public var onContentSizeChange: ((_ contentSize: CGSize) -> Void)?

    lazy var markdownView: MarkdownView = {
        let view = MarkdownView()
        view.maxTextWidth = UIScreen.main.bounds.width - 20
        view.backgroundColor = .clear
        view.onContentSizeChange = onContentSizeChange
        view.charactersPerFrame = 1
        view.frameInterval = 10
        return view
    }()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        message = ChatMessage(role: .assistant)
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        markdownView.box.addTo(contentView).top(10).leading(10).trailing(-10).bottom(-10)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
