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

// MARK: - 聊天气泡样式

/// 聊天界面的统一样式常量，保证三种 cell 的边距、圆角、配色完全一致。
enum ChatBubbleStyle {

    /// 气泡距离屏幕左右的边距。
    static let horizontalInset: CGFloat = 12
    /// 气泡距离 cell 上下的边距（相邻两条消息的实际间距 = 2 倍）。
    static let verticalInset: CGFloat = 6
    /// 气泡内部留白。
    static let contentInset = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    /// 头像边长。
    static let avatarSize: CGFloat = 30
    /// 头像与气泡之间的间距。
    static let avatarSpacing: CGFloat = 8
    /// 气泡圆角。
    static let cornerRadius: CGFloat = 16

    /// 气泡可占用的最大宽度（已扣除左右边距与头像）。
    static var maxBubbleWidth: CGFloat {
        UIScreen.main.bounds.width - horizontalInset * 2 - avatarSize - avatarSpacing
    }

    /// 助手气泡内 MarkdownView 的排版宽度。
    ///
    /// 助手消息常包含代码块 / 表格，气泡固定为最大宽度：
    /// 一是保证这些块级内容有足够空间，二是避免流式输出过程中气泡左右抖动。
    static var assistantContentWidth: CGFloat {
        maxBubbleWidth - contentInset.left - contentInset.right
    }

    /// 用户气泡的最大宽度：右侧留白，更接近常见聊天界面。
    static var maxUserBubbleWidth: CGFloat {
        min(maxBubbleWidth, UIScreen.main.bounds.width * 0.72)
    }

    /// 用户气泡内 MarkdownView 的最大排版宽度。
    static var maxUserContentWidth: CGFloat {
        maxUserBubbleWidth - contentInset.left - contentInset.right
    }

    // MARK: 配色（深色模式自动适配）

    /// 聊天页背景。
    static var pageBackground: UIColor { .systemGroupedBackground }
    /// 助手气泡背景。
    static var assistantBubbleColor: UIColor { .systemBackground }
    /// 助手气泡描边。
    static var assistantBorderColor: UIColor { UIColor.separator.withAlphaComponent(0.6) }
    /// 助手气泡文字色。
    static var assistantTextColor: UIColor { .label }
    /// 用户气泡背景。
    static var userBubbleColor: UIColor { .systemBlue }
    /// 用户气泡文字色。
    static var userTextColor: UIColor { .white }
    /// 头像底色。
    static var avatarBackground: UIColor { .systemGray5 }
}

// MARK: - 气泡基类

/// 聊天气泡 cell 基类：负责「头像 + 气泡」的骨架与角色对齐。
///
/// 子类只需在 `init` 中依次调用：
/// 1. `setupBubble(role:)` 搭建骨架；
/// 2. `installBubbleContent(_:)` 把自己的内容视图放进气泡。
class ChatBubbleCell: UITableViewCell {

    /// 消息气泡容器。所有内容都应放在它内部，而不是直接放在 `contentView` 上。
    let bubbleView = UIView()

    /// 头像。用 emoji + 圆形底色实现，避免额外的图片资源。
    private let avatarLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 按角色搭建气泡与头像布局。每个 cell 实例只需调用一次。
    ///
    /// - 助手：头像在左，气泡右边缘对齐到屏幕边距（占满可用宽度）；
    /// - 用户：头像在右，气泡宽度由内容决定，向左延伸。
    func setupBubble(role: ChatRole) {
        avatarLabel.textAlignment = .center
        avatarLabel.font = .systemFont(ofSize: 15)
        avatarLabel.backgroundColor = ChatBubbleStyle.avatarBackground
        avatarLabel.layer.cornerRadius = ChatBubbleStyle.avatarSize / 2
        avatarLabel.layer.masksToBounds = true

        bubbleView.layer.cornerRadius = ChatBubbleStyle.cornerRadius
        bubbleView.layer.masksToBounds = true

        switch role {
        case .assistant:
            avatarLabel.text = "🤖"
            bubbleView.backgroundColor = ChatBubbleStyle.assistantBubbleColor
            bubbleView.layer.borderWidth = 1
            bubbleView.layer.borderColor = ChatBubbleStyle.assistantBorderColor.cgColor
        case .user:
            avatarLabel.text = "🙂"
            bubbleView.backgroundColor = ChatBubbleStyle.userBubbleColor
            bubbleView.layer.borderWidth = 0
        }

        // 头像与气泡顶部对齐；气泡底部撑起 cell 高度（配合 automaticDimension）。
        avatarLabel.box
            .addTo(contentView)
            .top(ChatBubbleStyle.verticalInset)
            .square(ChatBubbleStyle.avatarSize)

        bubbleView.box
            .addTo(contentView)
            .top(ChatBubbleStyle.verticalInset)
            .bottom(-ChatBubbleStyle.verticalInset)

        switch role {
        case .assistant:
            avatarLabel.box.leading(ChatBubbleStyle.horizontalInset)
            // trailing 用等式：助手气泡占满可用宽度，代码块 / 表格不会被挤窄，
            // 流式输出时气泡宽度也保持稳定。
            bubbleView.box
                .leadingTo(avatarLabel.trailingAnchor, offset: ChatBubbleStyle.avatarSpacing)
                .trailing(-ChatBubbleStyle.horizontalInset)
        case .user:
            avatarLabel.box.trailing(-ChatBubbleStyle.horizontalInset)
            // leading 用不等式：气泡宽度由内容撑开（短消息就是小气泡），
            // 宽度上限由内容视图自身的 maxTextWidth 控制。
            bubbleView.box
                .trailingTo(avatarLabel.leadingAnchor, offset: -ChatBubbleStyle.avatarSpacing)
                .leadingGreaterThanOrTo(contentView.leadingAnchor, offset: ChatBubbleStyle.horizontalInset)
        }

        avatarLabel.box.flush()
        bubbleView.box.flush()
    }

    /// 把内容视图按统一内边距放进气泡。
    /// - Parameters:
    ///   - view: 内容视图。
    ///   - remake: 视图是否从别的父视图迁移而来（需要先清掉旧约束）。
    func installBubbleContent(_ view: UIView, remake: Bool = false) {
        let box = view.box
            .addTo(bubbleView)
            .top(ChatBubbleStyle.contentInset.top)
            .leading(ChatBubbleStyle.contentInset.left)
            .trailing(-ChatBubbleStyle.contentInset.right)
            .bottom(-ChatBubbleStyle.contentInset.bottom)

        if remake {
            // 复用共享视图时必须先失效上一个气泡里的约束，否则两套约束会冲突。
            box.remake()
        } else {
            box.flush()
        }
    }

    /// 生成一个放进气泡的 MarkdownView（背景透明，底色与圆角交给气泡）。
    static func makeBubbleMarkdownView(maxTextWidth: CGFloat,
                                       charactersPerFrame: Int,
                                       frameInterval: Int) -> MarkdownView {
        let view = MarkdownView()
        view.maxTextWidth = maxTextWidth
        view.charactersPerFrame = charactersPerFrame
        view.frameInterval = frameInterval
        view.backgroundColor = .clear
        // MarkdownView 内部的 UITextView 默认白底，不清掉会在气泡里露出白色方块。
        view.textView.backgroundColor = .clear
        return view
    }
}

// MARK: - 用户消息

class UserTableCell: ChatBubbleCell {

    var message: ChatMessage {
        willSet {
            let att = NSAttributedString(
                string: newValue.markdown,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: ChatBubbleStyle.userTextColor
                ]
            )
            markdownView.attributedText(att)
        }
    }

    public var onContentSizeChange: ((_ contentSize: CGSize) -> Void)?

    lazy var markdownView: MarkdownView = ChatBubbleCell.makeBubbleMarkdownView(
        maxTextWidth: ChatBubbleStyle.maxUserContentWidth,
        charactersPerFrame: 3,
        frameInterval: 10
    )

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        message = ChatMessage(role: .user)
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupBubble(role: .user)
        installBubbleContent(markdownView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        markdownView.onContentSizeChange = nil
        markdownView.clearTextViewAttributes()
    }
}

// MARK: - 助手消息（已完成）

class ChatTableCell: ChatBubbleCell {

    var message: ChatMessage {
        willSet {
            if newValue.isFinished {
                markdownView.attributedText(newValue.attributedString)
            }
            markdownView.identifier = newValue.id
        }
    }

    public var onContentSizeChange: ((_ contentSize: CGSize) -> Void)?

    lazy var markdownView: MarkdownView = ChatBubbleCell.makeBubbleMarkdownView(
        maxTextWidth: ChatBubbleStyle.assistantContentWidth,
        charactersPerFrame: 10,
        frameInterval: 20
    )

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        message = ChatMessage(role: .assistant)
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupBubble(role: .assistant)
        installBubbleContent(markdownView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        markdownView.onContentSizeChange = nil
        markdownView.clearTextViewAttributes()
    }
}

// MARK: - 助手消息（流式中）

/// 正在流式输出的助手消息。
///
/// 它不持有自己的 MarkdownView：整个会话共用控制器里的那一个，
/// 由控制器通过 `attach(_:)` 挂进气泡，避免流式状态随 cell 复用被打断。
class AssistTableCell: ChatBubbleCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupBubble(role: .assistant)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 把外部共享的流式 MarkdownView 挂到气泡里（已在气泡内则不重复搬运）。
    func attach(_ markdownView: MarkdownView) {
        guard markdownView.superview !== bubbleView else { return }
        markdownView.removeFromSuperview()
        installBubbleContent(markdownView, remake: true)
    }
}
