//
//  File.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/9/3.
//

import UIKit
@available(iOS 13.0, *)
public struct CodeBlockOption {

    /// 代码块最大宽度（<=0 表示用宿主可用宽度）。
    public var maxWidth: CGFloat = 0
    /// 代码块最大高度（<=0 表示不限制，超出可垂直滚动）。
    public var maxHeight: CGFloat = 0
    /// 单行代码最大宽度（>0 超出换行）。
    public var maxCellWidth: CGFloat = 0

    /// 是否展示行号。
    public var showsLineNumbers: Bool = true
    /// 代码区是否允许水平滚动（关闭后长行会换行完整展示，行号仍按 `\n` 计数）。
    public var allowsHorizontalScroll: Bool = true
    /// 代码区是否允许垂直滚动。
    public var allowsVerticalScroll: Bool = true

    /// 代码字体。
    public var codeFont: UIFont = UIFont(name: "Menlo", size: 13) ?? .systemFont(ofSize: 13)
    /// 行号字体。
    public var lineNumberFont: UIFont = UIFont(name: "Menlo", size: 13) ?? .systemFont(ofSize: 13)
    /// 行号文字颜色。
    public var lineNumberColor: UIColor = UIColor(white: 0.55, alpha: 1)
    /// 行号栏背景色。
    public var gutterBackgroundColor: UIColor = UIColor(white: 0.96, alpha: 1)
    /// 代码区背景色。
    public var codeBackgroundColor: UIColor = UIColor(white: 0.98, alpha: 1)

    /// 头部背景色。
    public var headerBackgroundColor: UIColor = UIColor(white: 0.93, alpha: 1)
    /// 头部语言 / 默认文字颜色。
    public var headerTextColor: UIColor = .darkGray
    /// 头部字体。
    public var headerFont: UIFont = .monospacedSystemFont(ofSize: 12, weight: .semibold)
    /// 未检测出语言时头部展示的默认文字。
    public var defaultTitle: String = "代码"
    /// 复制按钮标题。
    public var copyTitle: String = "复制"
    /// 复制成功后的临时标题。
    public var copiedTitle: String = "已复制"
    /// 复制按钮的着色。
    public var copyButtonTintColor: UIColor = .systemBlue
    /// 边框颜色。
    public var borderColor: UIColor = UIColor(white: 0.85, alpha: 1)
    /// 圆角。
    public var cornerRadius: CGFloat = 8

    /// 复制回调（默认已写入系统剪贴板；此回调用于额外处理，如埋点 / 自定义提示）。
    public var onCopy: ((_ code: String) -> Void)?

    public init() {}
}
@available(iOS 13.0, *)
public final class CodeBlockHeaderView: UIView {

    private let titleLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let onCopy: () -> Void
    private let copyTitle: String
    private let copiedTitle: String
    private var resetWorkItem: DispatchWorkItem?

    init(title: String, config: CodeBlockOption, onCopy: @escaping () -> Void) {
        self.onCopy = onCopy
        self.copyTitle = config.copyTitle
        self.copiedTitle = config.copiedTitle
        super.init(frame: .zero)

        backgroundColor = config.headerBackgroundColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = config.headerFont
        titleLabel.textColor = config.headerTextColor
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.setTitle(config.copyTitle, for: .normal)
        copyButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        copyButton.tintColor = config.copyButtonTintColor
        copyButton.setTitleColor(config.copyButtonTintColor, for: .normal)
        if let doc = UIImage(systemName: "doc.on.doc") {
            copyButton.setImage(doc, for: .normal)
            copyButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 0)
        }
        copyButton.addTarget(self, action: #selector(onTapCopy), for: .touchUpInside)
        copyButton.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(copyButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 34),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 6),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),

            copyButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            copyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func onTapCopy() {
        onCopy()
        // 临时反馈「已复制」。
        copyButton.setTitle(copiedTitle, for: .normal)
        resetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.copyButton.setTitle(self.copyTitle, for: .normal)
        }
        resetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}

import Splash
public  func highlightedCode(_ code: String,
                                    language: String?,
                                    fontSize: CGFloat,
                                    textColor: UIColor) -> NSAttributedString {
    let monoFont = UIFont(name: "Menlo", size: fontSize - 1) ?? .systemFont(ofSize: fontSize - 1)
    let plain = NSAttributedString(string: code, attributes: [.font: monoFont, .foregroundColor: textColor])

    guard language?.lowercased() == "swift" else { return plain }

    let theme = Theme(font: Splash.Font(size: Double(fontSize - 1)),
                      plainTextColor: textColor,
                      tokenColors: [
                        .keyword: UIColor.systemPink,
                        .string: UIColor.systemRed,
                        .type: UIColor(red: 0.4, green: 0.2, blue: 0.7, alpha: 1),
                        .call: UIColor.systemBlue,
                        .number: UIColor.systemOrange,
                        .comment: UIColor(red: 0.3, green: 0.6, blue: 0.3, alpha: 1),
                        .property: UIColor.systemTeal,
                        .dotAccess: UIColor.systemBlue,
                        .preprocessing: UIColor.systemBrown
                      ],
                      backgroundColor: .clear)
    let highlighter = SyntaxHighlighter(format: AttributedStringOutputFormat(theme: theme))
    let highlighted = highlighter.highlight(code)
    return highlighted.length > 0 ? highlighted : plain
}
