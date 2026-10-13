//
//  MathFormulaDemoViewController.swift
//  SwiftMarkdownViewKit_Example
//
//  `MathJaxWebView` 的可视化 Demo：把排版出来的 SVG 图片真正画到页面上。
//
//  三个区域分别验证三件事：
//    1. 块级公式  → 拿到的 UIImage 能不能正常显示、清不清晰
//    2. 行内公式  → baselineOffset 是否正确（公式能否和文字对齐）
//    3. 自动抽取  → MathFormula.formulas(in:) 能否从 Markdown 里把公式找全
//

import UIKit
import SwiftMarkdownViewKit

final class MathFormulaDemoViewController: UIViewController {

    // MARK: - 数据

    /// 块级公式样本。
    private let blockSamples: [(title: String, latex: String)] = [
        ("质能方程",   #"E = mc^2"#),
        ("求根公式",   #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#),
        ("高斯积分",   #"\int_{0}^{\infty} e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}"#),
        ("求和",      #"\sum_{i=1}^{n} i = \frac{n(n+1)}{2}"#),
        ("矩阵",      #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}\begin{pmatrix} x \\ y \end{pmatrix}"#),
        ("极限",      #"\lim_{x \to 0} \frac{\sin x}{x} = 1"#)
    ]

    /// 用于验证「自动抽取」的 Markdown 原文。
    private let markdownSample = """
    爱因斯坦提出了 $E = mc^2$，其中 $c$ 是光速。

    一元二次方程的解为：

    $$x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$$

    这段代码里的 `$notMath$` 不应该被识别。

    商品售价 $100 也不应该被识别。
    """

    // MARK: - 视图

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    /// 正文字号。公式大小跟它走，保证和文字视觉一致。
    private let bodyFontSize: CGFloat = 17

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "数学公式渲染"
        view.backgroundColor = .systemGroupedBackground

        setupScrollView()

        // 统一排版参数：颜色跟随深色模式，字号与正文一致。
        var options = MathRenderOptions()
        options.textColor = .label
        options.fontSize = bodyFontSize
        MathJaxWebView.shared.options = options

        buildBlockSection()
        buildInlineSection()
        buildExtractionSection()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        // 公式颜色在排版时就写进 SVG 了，深色模式切换后必须清缓存重排，
        // 否则浅色模式下排出来的黑色公式在深色背景上会看不见。
        guard #available(iOS 13.0, *),
              traitCollection.hasDifferentColorAppearance(comparedTo: previous) else { return }
        MathJaxWebView.shared.clearCache()
        reloadAll()
    }

    // MARK: - 布局骨架

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        let guide = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -32),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor,
                                             constant: -32)
        ])
    }

    private func reloadAll() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        buildBlockSection()
        buildInlineSection()
        buildExtractionSection()
    }

    // MARK: - 区域一：块级公式

    private func buildBlockSection() {
        stackView.addArrangedSubview(makeSectionHeader("块级公式（displayMode = true）"))

        for sample in blockSamples {
            let card = FormulaCard(title: sample.title, latex: sample.latex)
            stackView.addArrangedSubview(card)

            MathJaxWebView.shared.render(sample.latex, displayMode: true) { [weak card] result in
                switch result {
                case .success(let output):
                    card?.show(output)
                case .failure(let error):
                    card?.showError(error)
                }
            }
        }
    }

    // MARK: - 区域二：行内公式

    private func buildInlineSection() {
        stackView.addArrangedSubview(makeSectionHeader("行内公式（displayMode = false）"))

        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: bodyFontSize)
        label.textColor = .label

        let container = makeCardContainer()
        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        stackView.addArrangedSubview(container)

        // 把文字和公式拼成一串：公式用 NSTextAttachment 插进去，
        // 关键是 makeAttachment() 已经把 baselineOffset 写进 bounds.origin.y，
        // 所以分数线、下标能和周围文字正确对齐。
        let pieces: [(text: String, latex: String?)] = [
            ("质能方程 ", nil), ("", "E = mc^2"),
            (" 描述质能关系；当 ", nil), ("", "x^2 + y_1 \\geq 0"),
            (" 时，", nil), ("", "\\frac{a}{b}"),
            (" 有意义。再看一个根式 ", nil), ("", "\\sqrt[3]{x+1}"),
            (" 和求和 ", nil), ("", "\\sum_{i=1}^{n} a_i"),
            (" 的行内效果。下面这条特意写得很宽，用来验证超宽时会等比缩小而不是被裁切：", nil),
            ("", "\\int_{-\\infty}^{+\\infty} e^{-\\alpha x^2 + \\beta x}\\,dx = \\sqrt{\\frac{\\pi}{\\alpha}}\\,e^{\\frac{\\beta^2}{4\\alpha}}"),
            ("。", nil)
        ]

        // 文本可用宽度 = 屏宽 − 页面左右边距(16×2) − 卡片内边距(14×2)
        let availableWidth = UIScreen.main.bounds.width - 32 - 28

        let result = NSMutableAttributedString()
        let group = DispatchGroup()
        var attachments: [Int: NSTextAttachment] = [:]

        for (index, piece) in pieces.enumerated() {
            guard let latex = piece.latex else { continue }
            group.enter()
            MathJaxWebView.shared.render(latex, displayMode: false) { output in
                if case .success(let value) = output {
                    // 传 maxWidth：超宽公式等比缩小，不会突破文本容器被裁掉右半截。
                    attachments[index] = value.makeAttachment(maxWidth: availableWidth)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak label] in
            for (index, piece) in pieces.enumerated() {
                if let attachment = attachments[index] {
                    result.append(NSAttributedString(attachment: attachment))
                } else if let latex = piece.latex {
                    // 排版失败时退回显示原始 LaTeX，不要让这段文字凭空消失。
                    result.append(NSAttributedString(string: "$\(latex)$"))
                } else {
                    result.append(NSAttributedString(string: piece.text))
                }
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 8
            result.addAttributes([
                .font: UIFont.systemFont(ofSize: self.bodyFontSize),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph
            ], range: NSRange(location: 0, length: result.length))
            label?.attributedText = result
        }
    }

    // MARK: - 区域三：从 Markdown 自动抽取

    private func buildExtractionSection() {
        stackView.addArrangedSubview(makeSectionHeader("从 Markdown 自动抽取"))

        let source = UILabel()
        source.numberOfLines = 0
        source.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        source.textColor = .secondaryLabel
        source.text = markdownSample

        let sourceCard = makeCardContainer()
        sourceCard.addSubview(source)
        source.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            source.topAnchor.constraint(equalTo: sourceCard.topAnchor, constant: 14),
            source.leadingAnchor.constraint(equalTo: sourceCard.leadingAnchor, constant: 14),
            source.trailingAnchor.constraint(equalTo: sourceCard.trailingAnchor, constant: -14),
            source.bottomAnchor.constraint(equalTo: sourceCard.bottomAnchor, constant: -14)
        ])
        stackView.addArrangedSubview(sourceCard)

        let formulas = MathFormula.formulas(in: markdownSample)

        let summary = UILabel()
        summary.font = .systemFont(ofSize: 13, weight: .medium)
        summary.textColor = .secondaryLabel
        summary.text = "抽取到 \(formulas.count) 条公式（`$notMath$` 与 $100 应被正确排除）"
        summary.numberOfLines = 0
        stackView.addArrangedSubview(summary)

        // 批量排版：一次调用，结果与入参顺序严格对应。
        MathJaxWebView.shared.render(formulas) { [weak self] results in
            guard let self = self else { return }
            for (formula, result) in zip(formulas, results) {
                let card = FormulaCard(title: formula.isDisplayMode ? "块级" : "行内",
                                       latex: formula.latex)
                self.stackView.addArrangedSubview(card)
                switch result {
                case .success(let output): card.show(output)
                case .failure(let error): card.showError(error)
                }
            }
        }
    }

    // MARK: - 小工具

    private func makeSectionHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    private func makeCardContainer() -> UIView {
        let v = UIView()
        v.backgroundColor = .secondarySystemGroupedBackground
        v.layer.cornerRadius = 10
        return v
    }
}

// MARK: - 单条公式卡片

/// 展示一条公式：标题 + LaTeX 源码 + 排版出来的图片 + 尺寸信息。
///
/// 图片采用**等比自适应**：
/// - 原始宽度放得下 → 按 1:1 原始尺寸显示（最清晰）；
/// - 放不下（矩阵、长积分式）→ 宽度收到容器边界，高度按宽高比自动跟随，不会被压扁。
private final class FormulaCard: UIView {

    private let titleLabel = UILabel()
    private let latexLabel = UILabel()
    private let formulaImageView = UIImageView()
    private let infoLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    private let contentStack = UIStackView()

    /// 占位 / 失败态用的固定高度。排版成功后会被停用，改由宽高比决定高度。
    private var placeholderHeight: NSLayoutConstraint!

    /// 宽高比约束（必需级）。公式一变就要重建，因为比例不同。
    private var aspectRatioConstraint: NSLayoutConstraint?

    /// 期望宽度 = 公式原始宽度。
    ///
    /// 优先级故意设成 `.defaultHigh`（750），低于下面的「不超过容器宽度」约束（1000）。
    /// 这样 Auto Layout 会自己做选择：
    ///   放得下 → 满足期望宽度，原始尺寸显示；
    ///   放不下 → 牺牲期望宽度，贴着容器边界，高度由宽高比跟着缩。
    private var preferredWidthConstraint: NSLayoutConstraint?

    init(title: String, latex: String) {
        super.init(frame: .zero)
        setup()
        titleLabel.text = title
        latexLabel.text = latex
        spinner.startAnimating()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 10

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .label

        latexLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        latexLabel.textColor = .tertiaryLabel
        latexLabel.numberOfLines = 0

        formulaImageView.contentMode = .scaleAspectFit
        // 关掉 UIImageView 自带的内容尺寸推断：
        // 它会用图片像素尺寸生成 intrinsicContentSize，和我们手动加的
        // 宽高比 / 期望宽度约束打架，在宽公式上会报约束冲突。
        formulaImageView.setContentHuggingPriority(.init(1), for: .horizontal)
        formulaImageView.setContentHuggingPriority(.init(1), for: .vertical)
        formulaImageView.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        formulaImageView.setContentCompressionResistancePriority(.init(1), for: .vertical)

        infoLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        infoLabel.textColor = .tertiaryLabel
        infoLabel.numberOfLines = 0

        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        [titleLabel, latexLabel, formulaImageView, infoLabel].forEach {
            contentStack.addArrangedSubview($0)
        }
        addSubview(contentStack)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)

        placeholderHeight = formulaImageView.heightAnchor.constraint(equalToConstant: 30)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),

            // 必需级：永远不许超出卡片内容区
            formulaImageView.widthAnchor.constraint(lessThanOrEqualTo: contentStack.widthAnchor),
            placeholderHeight,

            spinner.leadingAnchor.constraint(equalTo: formulaImageView.leadingAnchor),
            spinner.centerYAnchor.constraint(equalTo: formulaImageView.centerYAnchor)
        ])
    }

    func show(_ output: MathRenderOutput) {
        spinner.stopAnimating()
        formulaImageView.image = output.image

        let size = output.size
        guard size.width > 0, size.height > 0 else {
            showError(.invalidLatex("排版结果尺寸无效"))
            return
        }

        // 换公式时先拆掉上一组，否则旧的宽高比会和新的冲突。
        aspectRatioConstraint?.isActive = false
        preferredWidthConstraint?.isActive = false
        placeholderHeight.isActive = false

        let aspect = formulaImageView.widthAnchor.constraint(
            equalTo: formulaImageView.heightAnchor,
            multiplier: size.width / size.height
        )
        aspect.priority = .required
        aspect.isActive = true
        aspectRatioConstraint = aspect

        let preferred = formulaImageView.widthAnchor.constraint(equalToConstant: size.width)
        preferred.priority = .defaultHigh
        preferred.isActive = true
        preferredWidthConstraint = preferred

        infoLabel.textColor = .tertiaryLabel
        infoLabel.text = String(
            format: "原始 %.1f × %.1f pt   baseline %.2f pt   svg %d 字节",
            size.width, size.height, output.baselineOffset, output.svg.utf8.count
        )

        setNeedsLayout()
    }

    func showError(_ error: MathRenderError) {
        spinner.stopAnimating()
        formulaImageView.image = nil

        aspectRatioConstraint?.isActive = false
        preferredWidthConstraint?.isActive = false
        aspectRatioConstraint = nil
        preferredWidthConstraint = nil

        placeholderHeight.constant = 1
        placeholderHeight.isActive = true

        infoLabel.textColor = .systemRed
        infoLabel.text = "渲染失败：\(error.localizedDescription)"
    }

    /// 补充一行「实际显示尺寸」，方便肉眼确认宽公式确实等比缩小了。
    override func layoutSubviews() {
        super.layoutSubviews()
        guard formulaImageView.image != nil,
              let preferred = preferredWidthConstraint else { return }

        let shown = formulaImageView.bounds.size
        guard shown.width > 0 else { return }

        let scale = shown.width / preferred.constant
        let suffix = scale < 0.995
            ? String(format: "   实际 %.1f × %.1f pt（等比缩至 %.0f%%）",
                     shown.width, shown.height, scale * 100)
            : "   实际 1:1 显示"

        // 只在后缀变化时改文案，避免 layoutSubviews 里反复触发重排。
        if let text = infoLabel.text, !text.hasSuffix(suffix) {
            let base = text.components(separatedBy: "   实际").first ?? text
            infoLabel.text = base + suffix
        }
    }
}
