//
//  CarouselView.swift
//  MarkdownViewKit
//
//  图片组（轮播 / 横滑相册）视图，遵循项目的 `ViewLoadable` 插件规则：
//    - `regxRule()` 匹配 `<carousel> ... </carousel>` 语法块；
//    - 块内既支持标准 Markdown 图片 `![alt](url)`，也支持裸 URL / `<img src="">`；
//    - 基于 `UICollectionView` + Compositional Layout 实现横向左右滑动；
//    - 图片间距、单张图片尺寸、圆角、内边距等均可通过 `CarouselOption` 配置；
//    - 图片点击事件通过 `onImageTapped` 外传，默认接入 `ImagePreviewer` 全屏预览。
//

import UIKit
import SDWebImage
import Markdown
// MARK: - 数据模型

/// 图片组单项数据：一张图片 + 它自己的小标题。
public struct CarouselItem {

    /// 图片地址。
    public var url: String

    /// 图片下方展示的小标题，留空则不占位。
    public var title: String

    public init(url: String, title: String = "") {
        self.url = url
        self.title = title
    }
}

/// `(url, title)` 元组写法，方便外部直接用字面量传值。
public typealias CarouselItemTuple = (url: String, title: String)

// MARK: - 配置

/// 图片组展示配置。
public struct CarouselOption {

    /// 单张图片尺寸（不含图片间内边距）。
    public var itemSize: CGSize = CGSize(width: 140, height: 140)

    /// 图片之间的横向间隔。
    public var itemSpacing: CGFloat = 8

    /// 图片组四周内边距（左右会形成首尾留白）。
    public var contentInset: UIEdgeInsets = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)

    /// 单张图片圆角。
    public var cornerRadius: CGFloat = 8

    /// 图片填充模式。
    public var contentMode: UIView.ContentMode = .scaleAspectFill

    /// 占位图。
    public var placeholderImage: UIImage? = nil

    /// 图片背景色（加载中 / 透明图时可见）。
    public var itemBackgroundColor: UIColor = UIColor(white: 0.94, alpha: 1.0)

    /// 整体背景色。
    public var backgroundColor: UIColor = .clear

    /// 是否显示横向滚动条。
    public var showsScrollIndicator: Bool = false

    /// 点击图片时是否使用内置的 `ImagePreviewer` 全屏预览（`onImageTapped` 返回 false / 未设置时生效）。
    public var usesBuiltinPreview: Bool = true

    /// 是否展示标题（`<carousel>` 块内 `title: xxx` 行）。
    public var showsTitle: Bool = true

    /// 标题字体。
    public var titleFont: UIFont = .boldSystemFont(ofSize: 15)

    /// 标题颜色。
    public var titleColor: UIColor = .darkText

    /// 标题最大行数（0 表示不限制）。
    public var titleNumberOfLines: Int = 2

    /// 标题四周内边距。
    public var titleInset: UIEdgeInsets = UIEdgeInsets(top: 4, left: 2, bottom: 0, right: 2)

    /// 标题与图片之间的垂直间距。
    public var titleSpacing: CGFloat = 6

    // MARK: 单项小标题（每张图片下方）

    /// 是否展示每张图片下方的小标题。
    ///
    /// 仅当至少有一项的 `title` 非空时才会真正占用高度，
    /// 所以纯图片场景下开着它也不会多出空白。
    public var showsItemTitle: Bool = true

    /// 单项小标题字体。
    public var itemTitleFont: UIFont = .systemFont(ofSize: 12)

    /// 单项小标题颜色。
    public var itemTitleColor: UIColor = .darkGray

    /// 单项小标题最大行数（至少 1 行）。
    public var itemTitleNumberOfLines: Int = 1

    /// 单项小标题与图片之间的垂直间距。
    public var itemTitleSpacing: CGFloat = 4

    /// 单项小标题对齐方式。
    public var itemTitleAlignment: NSTextAlignment = .center

    public init() {}
}

// MARK: - Cell

final class CarouselCell: UICollectionViewCell {

    static let reuseID = "CarouselCell"

    let imageView = UIImageView()

    /// 图片下方的小标题。
    let titleLabel = UILabel()

    /// 小标题高度约束：无标题时压到 0，避免留白。
    private var titleHeightConstraint: NSLayoutConstraint!

    /// 图片与小标题之间的间距约束。
    private var titleTopConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // 图片没有 bottom 约束——它的底边由小标题的 top 约束决定，
        // 这样小标题高度压到 0 时图片会自动撑满整个 cell。
        titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor)
        titleHeightConstraint = titleLabel.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            titleTopConstraint,
            titleHeightConstraint,
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.sd_cancelCurrentImageLoad()
        imageView.image = nil
        titleLabel.text = nil
    }

    /// 配置单元格。
    ///
    /// - Parameters:
    ///   - item: 图片与小标题数据。
    ///   - option: 展示配置。
    ///   - titleAreaHeight: 小标题区（含间距）的总高度，由 `CarouselView` 统一计算后下发。
    ///     所有 cell 必须使用同一个值，否则图片高度会参差不齐。
    func configure(item: CarouselItem,
                   option: CarouselOption,
                   titleAreaHeight: CGFloat,
                   onLoaded: ((UIImage?) -> Void)? = nil) {
        imageView.contentMode = option.contentMode
        imageView.backgroundColor = option.itemBackgroundColor
        imageView.layer.cornerRadius = option.cornerRadius
        imageView.clipsToBounds = true

        // 圆角只作用在图片上：小标题跟着一起裁切会显得很怪。
        contentView.layer.cornerRadius = 0
        contentView.clipsToBounds = false

        // 小标题。
        let showsTitle = titleAreaHeight > 0
        titleLabel.isHidden = !showsTitle
        titleLabel.font = option.itemTitleFont
        titleLabel.textColor = option.itemTitleColor
        titleLabel.numberOfLines = max(option.itemTitleNumberOfLines, 1)
        titleLabel.textAlignment = option.itemTitleAlignment
        titleLabel.text = showsTitle ? item.title : nil
        titleTopConstraint.constant = showsTitle ? option.itemTitleSpacing : 0
        titleHeightConstraint.constant = max(titleAreaHeight - option.itemTitleSpacing, 0)

        guard let url = URL(string: item.url) else {
            imageView.image = option.placeholderImage
            onLoaded?(nil)
            return
        }
        imageView.sd_setImage(with: url, placeholderImage: option.placeholderImage) { image, _, _, _ in
            onLoaded?(image)
        }
    }
}

// MARK: - CarouselView

@available(iOS 13.0, *)
public class CarouselView: UIView, UICollectionViewDataSource, UICollectionViewDelegate, ViewLoadable {
    public func updateData(data: MarkupContext<Markdown.Paragraph>) {
        if let data = parseData(data: data) {
            update(items: data)
        }
    }
    
   
    public func startStreaming(data: MarkupContext<Markdown.Paragraph>, animation: Bool) {
        isContentClosed = true
        if let data = parseData(data: data) {
            update(items: data)
        }
        onStreamingFinished?()
    }
    
    public func estimatedSize(for data: MarkupContext<Markdown.Paragraph>) -> CGSize {
        viewOptions.estimedSize ?? .zero
    }
    
    public typealias MarkupType = Paragraph
    

    public var viewOptions: ViewOption = ViewOption()
    
    
    private func parseData(data: MarkupContext<Markdown.Paragraph>)-> [CarouselItem]? {
        let source = data.markup.format() as NSString
        if let match = data.match {
            let text = source.substring(with: match.range) as String
            let images = text.split(separator: "\n")
           return images.map {
               parseMarkdownImages(String($0))
           }.flatMap {$0}
        }
        return nil
    }
    
    private func parseMarkdownImages(_ markdown: String) -> [CarouselItem] {
        let pattern = #"!\[([^\]]*)\]\(([^)\r\n]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsRange = NSRange(
            location: 0,
            length: (markdown as NSString).length
        )
        return regex.matches(in: markdown, range: nsRange).compactMap { match in
            guard match.numberOfRanges >= 3 else {return nil}
            let nsString = markdown as NSString
            let title = nsString.substring(with: match.range(at: 1))
            let url = nsString.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else {return nil}
            return CarouselItem(url: url,title: title)
        }
    }

    /// 图片组配置。
    public var option = CarouselOption() {
        didSet { applyOptionAndReload() }
    }

    /// 图片数据（URL + 各自的小标题）。
    public private(set) var items: [CarouselItem] = []

    /// 图片 URL 列表（由 `items` 派生，保持既有调用方兼容）。
    public var imageURLs: [String] { items.map { $0.url } }

    /// 图片组标题（`<carousel>` 块内 `title: xxx` 行）。
    public private(set) var title: String = ""

    /// 内容是否已闭合（即 `</carousel>` 结束标签是否已到达）。
    /// 流式过程中未闭合时为 `false`，此时展示光晕占位图而非真实图片。
    public private(set) var isContentClosed: Bool = false

    /// 已加载成功的图片缓存（key 为 URL），用于点击预览。
    private var loadedImages: [String: UIImage] = [:]

    /// 图片点击回调：返回 `true` 表示外部已自行处理（不再触发内置预览）。
    /// 参数：当前视图、被点击的下标、全部图片 URL。
    public var onImageTapped: ((CarouselView, Int, [String]) -> Bool)?

    public var onContentSizeChanged: ((CGSize) -> Void)?

    public var onStreamingFinished: (() -> Void)?

    private var lastNotifiedSize: CGSize = .zero
    private var lastParsedContent: String?
    public func estimatedSize(for data: TextMatch) -> CGSize {
        return preferredSize()
    }

    public func attachmentContentInset() -> UIEdgeInsets {
        .init(top: 5, left: 5, bottom: 5, right: 5)
    }

    /// 容器可用宽度变化（横竖屏 / 分屏）时重新测量。
    ///
    /// 图片本身是固定尺寸的，但整体标题会因为宽度变化而改变折行行数，
    /// 进而影响自身高度，所以这里要重算并上报。
    public func updateViewOptions(_ options: ViewOption) {
        updateTitleLayout()
        invalidateIntrinsicContentSize()
        notifyContentSizeChangeIfNeeded()
    }

    // MARK: 初始化

    public required init() {
        super.init(frame: .zero)
        setup()
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: bounds, collectionViewLayout: makeLayout())
        cv.backgroundColor = .clear
        cv.dataSource = self
        cv.delegate = self
        cv.showsHorizontalScrollIndicator = option.showsScrollIndicator
        cv.showsVerticalScrollIndicator = false
        cv.alwaysBounceHorizontal = true
        cv.alwaysBounceVertical = false
        cv.contentInsetAdjustmentBehavior = .never
        cv.register(CarouselCell.self, forCellWithReuseIdentifier: CarouselCell.reuseID)
        return cv
    }()

    /// 标题标签（位于图片组顶部）。
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = option.titleFont
        label.textColor = option.titleColor
        label.numberOfLines = option.titleNumberOfLines
        return label
    }()

    /// 标题相关约束（随标题显隐更新）。
    private var titleTopConstraint: NSLayoutConstraint!
    private var titleHeightConstraint: NSLayoutConstraint!
    private var collectionTopConstraint: NSLayoutConstraint!

    /// 未闭合时展示的占位容器（浅色圆角背景）。
    private lazy var placeholderContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.94, alpha: 1.0)
        v.layer.cornerRadius = option.cornerRadius
        v.clipsToBounds = true
        v.isUserInteractionEnabled = false
        return v
    }()

    /// 光晕扫描动画层（贴在占位容器之上）。
    private lazy var shimmerView: ShimmerOverlayView = {
        let s = ShimmerOverlayView()
        s.isUserInteractionEnabled = false
        s.layer.cornerRadius = option.cornerRadius
        return s
    }()

    private func setup() {
        clipsToBounds = true
        backgroundColor = option.backgroundColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)

        // 光晕占位视图：覆盖图片区域（collectionView 的内容区），流式未闭合时显示。
        placeholderContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderContainer)
        shimmerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shimmerView)

        titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: option.titleInset.top)
        titleHeightConstraint = titleLabel.heightAnchor.constraint(equalToConstant: 0)
        collectionTopConstraint = collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor)

        NSLayoutConstraint.activate([
            titleTopConstraint,
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: option.titleInset.left),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -option.titleInset.right),
            titleHeightConstraint,
            collectionTopConstraint,
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            // 占位容器 & 光晕与图片区域对齐。
            placeholderContainer.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor, constant: option.contentInset.left),
            placeholderContainer.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor, constant: -option.contentInset.right),
            placeholderContainer.topAnchor.constraint(equalTo: collectionView.topAnchor, constant: option.contentInset.top),
            placeholderContainer.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: -option.contentInset.bottom),
            shimmerView.leadingAnchor.constraint(equalTo: placeholderContainer.leadingAnchor),
            shimmerView.trailingAnchor.constraint(equalTo: placeholderContainer.trailingAnchor),
            shimmerView.topAnchor.constraint(equalTo: placeholderContainer.topAnchor),
            shimmerView.bottomAnchor.constraint(equalTo: placeholderContainer.bottomAnchor),
        ])
        updateTitleLayout()
        updatePlaceholderVisibility()
    }

    /// 根据闭合状态切换「光晕占位」与「真实图片」的显隐。
    private func updatePlaceholderVisibility() {
        let showPlaceholder = !isContentClosed
        placeholderContainer.isHidden = !showPlaceholder
        shimmerView.isHidden = !showPlaceholder
        shimmerView.isAnimating = showPlaceholder
        collectionView.isHidden = showPlaceholder
    }

    /// 根据当前标题内容与配置更新标题的显隐、样式与约束。
    private func updateTitleLayout() {
        let hasTitle = option.showsTitle && !title.isEmpty
        titleLabel.isHidden = !hasTitle
        titleLabel.font = option.titleFont
        titleLabel.textColor = option.titleColor
        titleLabel.numberOfLines = option.titleNumberOfLines
        titleLabel.text = hasTitle ? title : nil

        titleTopConstraint.constant = hasTitle ? option.titleInset.top : 0
        titleHeightConstraint.constant = hasTitle ? titleHeight() : 0
        collectionTopConstraint.constant = hasTitle ? (option.titleInset.bottom + option.titleSpacing) : 0
    }

    /// 测量标题文本高度（受最大行数与可用宽度约束）。
    private func titleHeight() -> CGFloat {
        guard option.showsTitle, !title.isEmpty else { return 0 }
        let available = availableWidth() - option.titleInset.left - option.titleInset.right
        guard available > 0 else { return option.titleFont.lineHeight }
        let bounding = (title as NSString).boundingRect(
            with: CGSize(width: available, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: option.titleFont],
            context: nil)
        var h = ceil(bounding.height)
        if option.titleNumberOfLines > 0 {
            let maxH = ceil(option.titleFont.lineHeight * CGFloat(option.titleNumberOfLines))
            h = min(h, maxH)
        }
        return h
    }

    /// 可用宽度（优先用附件计算好的 maxWidth）。
    ///
    /// 这里必须用可选绑定：`update(items:)` 可能在视图挂到 Markdown 附件之前
    /// 就被业务方调用，此时 `viewOptions` 里的宽度还是 nil，强解包会直接崩溃。
    private func availableWidth() -> CGFloat {
        if let maxWidth = viewOptions.maxWidth, maxWidth > 0 { return maxWidth }
        if bounds.width > 0 { return bounds.width }
        if let estimated = viewOptions.estimedSize, estimated.width > 0 { return estimated.width }
        return ViewOption.defaultValue
    }

    /// 单项小标题区的总高度（含图片与标题之间的间距）。
    ///
    /// 只要所有项的标题都为空就返回 0，这样纯图片场景不会平白多出一截空白。
    /// 这个值会同时用于「布局 item 高度」「cell 内部约束」「自身高度估算」三处，
    /// 必须保持单一来源，否则三者对不上就会出现图片被压扁或标题被裁切。
    private var itemTitleAreaHeight: CGFloat {
        guard option.showsItemTitle,
              items.contains(where: { !$0.title.isEmpty }) else { return 0 }
        let lines = CGFloat(max(option.itemTitleNumberOfLines, 1))
        return ceil(option.itemTitleFont.lineHeight * lines) + option.itemTitleSpacing
    }

    /// 单个 item 的总高度 = 图片高 + 小标题区高。
    private var totalItemHeight: CGFloat {
        option.itemSize.height + itemTitleAreaHeight
    }

    // MARK: 数据

    /// 直接喂数据并刷新图片组。
    ///
    /// 用于脱离 Markdown 解析、由业务方直接驱动的场景。调用后会立刻把视图切到
    /// 「已闭合」状态（关闭光晕占位、显示真实图片），并重新计算自身高度上报给宿主。
    ///
    /// ```swift
    /// carousel.update(items: [
    ///     (url: "https://example.com/1.jpg", title: "第一张"),
    ///     (url: "https://example.com/2.jpg", title: "第二张")
    /// ], title: "相册")
    /// ```
    ///
    /// - Parameters:
    ///   - items: 图片与小标题的元组数组。
    ///   - title: 图片组整体标题；传 `nil` 表示保持当前标题不变。
    public func update(items: [CarouselItemTuple], title: String? = nil) {
        update(items: items.map { CarouselItem(url: $0.url, title: $0.title) }, title: title)
    }

    /// 直接喂数据并刷新图片组（结构体版本）。
    ///
    /// - Parameters:
    ///   - items: 图片数据。
    ///   - title: 图片组整体标题；传 `nil` 表示保持当前标题不变。
    public func update(items: [CarouselItem], title: String? = nil) {
        self.items = items
        if let title = title { self.title = title }

        // 外部直接给了数据，等同于内容已完整到达，关闭光晕占位。
        isContentClosed = true

        // 清空「上次解析的内容」缓存：否则后续若又有相同的 Markdown 文本流进来，
        // `apply(content:)` 会因为内容相同而被短路跳过，导致数据无法回到解析结果。
        lastParsedContent = nil

        // 图片可能整批换掉，旧的预览缓存不再有效。
        loadedImages.removeAll()

        refreshAll()
    }

    /// 只更新图片组整体标题。
    public func update(title: String) {
        self.title = title
        refreshAll()
    }

    /// 统一的刷新入口：重建布局 → 重载数据 → 重算高度并上报。
    ///
    /// 必须重建布局（而不是只 `reloadData`）：单项小标题的有无会改变 item 高度，
    /// 而 Compositional Layout 的尺寸是在创建时固化的。
    private func refreshAll() {
        updateTitleLayout()
        updatePlaceholderVisibility()
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
        invalidateIntrinsicContentSize()
        notifyContentSizeChangeIfNeeded()
    }

    /// 解析 `<carousel>...</carousel>` 内容并刷新（重复内容不重复解析）。
    private func apply(content: String) {
        guard content != lastParsedContent else { return }
        lastParsedContent = content
        // 是否已闭合：匹配到的整段文本里是否包含 `</carousel>` 结束标签。
        isContentClosed = content.range(of: "</carousel>", options: .caseInsensitive) != nil
        // 标题可提前展示；图片仅在完全闭合后才解析并展示。
        title = CarouselView.parseTitle(from: content)
        let urls = isContentClosed ? CarouselView.parseImageURLs(from: content) : []
        items = urls.map { CarouselItem(url: $0) }
        refreshAll()
    }

    private func applyOptionAndReload() {
        backgroundColor = option.backgroundColor
        collectionView.showsHorizontalScrollIndicator = option.showsScrollIndicator
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        placeholderContainer.layer.cornerRadius = option.cornerRadius
        shimmerView.layer.cornerRadius = option.cornerRadius
        updateTitleLayout()
        updatePlaceholderVisibility()
        collectionView.reloadData()
        invalidateIntrinsicContentSize()
        notifyContentSizeChangeIfNeeded()
    }

    /// 从 `<carousel>` 块内容中提取标题：匹配独占一行的 `title: xxx`（大小写不敏感）。
    static func parseTitle(from content: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "(?:^|[\\n\\r\\u2028\\u2029])[ \\t]*title[ \\t]*[:：][ \\t]*([^\\n\\r\\u2028\\u2029]+)",
                                                options: [.caseInsensitive]) else { return "" }
        let ns = content as NSString
        guard let m = re.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return "" }
        return ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }

    /// 从 `<carousel>` 块内容中提取图片 URL。
    /// 支持四种写法：
    ///   - 花括号图片 `{alt}(url)`（推荐：避免被 Down 当作 Markdown 链接解析而丢失 URL）；
    ///   - 标准 Markdown 图片 `![alt](url)` / 链接 `[alt](url)`；
    ///   - HTML `<img src="url">`；
    ///   - 独占一行的裸 URL。
    static func parseImageURLs(from content: String) -> [String] {
        var urls: [String] = []
        let ns = content as NSString
        let full = NSRange(location: 0, length: ns.length)

        // 1) 括号图片语法：`{alt}(url)` / `[alt](url)` / `![alt](url)`。
        //    开括号匹配 `[` 或 `{`，闭括号匹配 `]` 或 `}`，随后紧跟 `(url)`。
        if let re = try? NSRegularExpression(pattern: "[\\[\\{][^\\]\\}]*[\\]\\}]\\(\\s*([^)\\s]+)[^)]*\\)") {
            re.enumerateMatches(in: content, range: full) { m, _, _ in
                guard let m = m, m.numberOfRanges > 1 else { return }
                urls.append(ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        // 2) HTML <img src="url">
        if let re = try? NSRegularExpression(pattern: "<img[^>]*src=[\"']([^\"']+)[\"'][^>]*>",
                                             options: [.caseInsensitive]) {
            re.enumerateMatches(in: content, range: full) { m, _, _ in
                guard let m = m, m.numberOfRanges > 1 else { return }
                urls.append(ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        // 3) 兜底：若上面都没匹配到，按行提取裸 URL。
        if urls.isEmpty {
            let separators = CharacterSet(charactersIn: "\n\r\u{2028}\u{2029}")
            content.components(separatedBy: separators).forEach { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("http://") || t.hasPrefix("https://") { urls.append(t) }
            }
        }
        return urls
    }

    // MARK: 布局 / 尺寸

    private func makeLayout() -> UICollectionViewLayout {
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.scrollDirection = .horizontal

        let opt = option
        // 布局在创建时就把尺寸固化了，所以这里要把当前的小标题区高度一起算进去；
        // 数据变化导致该值变动时，`refreshAll()` 会重建布局。
        let itemHeight = max(totalItemHeight, 1)
        return UICollectionViewCompositionalLayout(sectionProvider: { _, _ in
            let size = NSCollectionLayoutSize(widthDimension: .absolute(max(opt.itemSize.width, 1)),
                                              heightDimension: .absolute(itemHeight))
            let item = NSCollectionLayoutItem(layoutSize: size)
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = opt.itemSpacing
            section.contentInsets = NSDirectionalEdgeInsets(top: opt.contentInset.top,
                                                            leading: opt.contentInset.left,
                                                            bottom: opt.contentInset.bottom,
                                                            trailing: opt.contentInset.right)
            return section
        }, configuration: config)
    }

    /// 图片组自适应尺寸：宽度撑满可用宽度，高度 = 标题区 +（可选间距）+ 图片区 + 上下内边距。
    private func preferredSize() -> CGSize {
        let width = availableWidth()
        var height = totalItemHeight + option.contentInset.top + option.contentInset.bottom
        if option.showsTitle, !title.isEmpty {
            height += option.titleInset.top + titleHeight() + option.titleInset.bottom + option.titleSpacing
        }
        return CGSize(width: ceil(width), height: ceil(height))
    }

    public override var intrinsicContentSize: CGSize {
        return preferredSize()
    }

    private func notifyContentSizeChangeIfNeeded() {
        let size = preferredSize()
        guard size != lastNotifiedSize else { return }
        lastNotifiedSize = size
        self.bounds = CGRect(origin: bounds.origin, size: size)
//        onContentSizeChanged?(size)
    }

    // MARK: UICollectionViewDataSource

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    public func collectionView(_ collectionView: UICollectionView,
                               cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CarouselCell.reuseID,
                                                      for: indexPath) as! CarouselCell
        let item = items[indexPath.item]
        cell.configure(item: item, option: option, titleAreaHeight: itemTitleAreaHeight) { [weak self] image in
            if let image = image { self?.loadedImages[item.url] = image }
        }
        return cell
    }

    // MARK: UICollectionViewDelegate

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let index = indexPath.item
        guard index < items.count else { return }

        // 外部优先处理。
        if let handled = onImageTapped?(self, index, imageURLs), handled { return }

        // 内置全屏预览：收集已加载成功的图片，定位到点击项。
        guard option.usesBuiltinPreview else { return }
        var images: [UIImage] = []
        var startIndex = 0
        for (i, item) in items.enumerated() {
            if let img = loadedImages[item.url] {
                if i == index { startIndex = images.count }
                images.append(img)
            }
        }
        guard !images.isEmpty else { return }
        ImagePreviewer.shared.present(images, startIndex: startIndex, from: self, allowsSwipe: true)
    }
}
