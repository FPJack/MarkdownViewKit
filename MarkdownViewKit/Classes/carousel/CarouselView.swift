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

    public init() {}
}

// MARK: - Cell

final class CarouselCell: UICollectionViewCell {

    static let reuseID = "CarouselCell"

    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.sd_cancelCurrentImageLoad()
        imageView.image = nil
    }

    func configure(urlString: String, option: CarouselOption, onLoaded: ((UIImage?) -> Void)? = nil) {
        imageView.contentMode = option.contentMode
        imageView.backgroundColor = option.itemBackgroundColor
        imageView.layer.cornerRadius = option.cornerRadius
        contentView.layer.cornerRadius = option.cornerRadius
        contentView.clipsToBounds = true

        guard let url = URL(string: urlString) else {
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

    public var viewOptions: ViewOption = ViewOption()

    /// 图片组配置。
    public var option = CarouselOption() {
        didSet { applyOptionAndReload() }
    }

    /// 图片 URL 列表。
    public private(set) var imageURLs: [String] = []

    /// 图片组标题（`<carousel>` 块内 `title: xxx` 行）。
    public private(set) var title: String = ""

    /// 已加载成功的图片缓存（key 为 URL），用于点击预览。
    private var loadedImages: [String: UIImage] = [:]

    /// 图片点击回调：返回 `true` 表示外部已自行处理（不再触发内置预览）。
    /// 参数：当前视图、被点击的下标、全部图片 URL。
    public var onImageTapped: ((CarouselView, Int, [String]) -> Bool)?

    public var onContentSizeChanged: ((CGSize) -> Void)?

    public var onStreamingFinished: (() -> Void)?

    private var lastNotifiedSize: CGSize = .zero
    private var lastParsedContent: String?

    // MARK: ViewLoadable

    public static func regxRule() -> RegxRule {
        // 匹配 <carousel> ... </carousel> 整块（大小写不敏感，`[\s\S]` 跨行）。
        return RegxRule(pattern: "<carousel>([\\s\\S]*?)</carousel>", options: [.anchorsMatchLines])
    }

    public func updateData(data: TextMatch) {
        apply(content: data.content)
    }

    public func startStreaming(data: TextMatch, animation: Bool) {
        apply(content: data.content)
        onStreamingFinished?()
    }

    public func estimatedSize(for data: TextMatch) -> CGSize {
        return preferredSize()
    }

    public func attachmentContentInset() -> UIEdgeInsets {
        .init(top: 5, left: 5, bottom: 5, right: 5)
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

    private func setup() {
        clipsToBounds = true
        backgroundColor = option.backgroundColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)

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
        ])
        updateTitleLayout()
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
    private func availableWidth() -> CGFloat {
        if viewOptions.maxWidth > 0 { return viewOptions.maxWidth }
        if bounds.width > 0 { return bounds.width }
        return viewOptions.estimedSize.width
    }

    // MARK: 数据

    /// 解析 `<carousel>...</carousel>` 内容并刷新（重复内容不重复解析）。
    private func apply(content: String) {
        guard content != lastParsedContent else { return }
        lastParsedContent = content
        title = CarouselView.parseTitle(from: content)
        imageURLs = CarouselView.parseImageURLs(from: content)
        updateTitleLayout()
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
        invalidateIntrinsicContentSize()
        notifyContentSizeChangeIfNeeded()
    }

    private func applyOptionAndReload() {
        backgroundColor = option.backgroundColor
        collectionView.showsHorizontalScrollIndicator = option.showsScrollIndicator
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        updateTitleLayout()
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
    /// 支持三种写法：Markdown 图片 `![alt](url)`、HTML `<img src="url">`、独占一行的裸 URL。
    static func parseImageURLs(from content: String) -> [String] {
        var urls: [String] = []
        let ns = content as NSString
        let full = NSRange(location: 0, length: ns.length)

        // 1) Markdown 图片语法 ![alt](url)
        if let re = try? NSRegularExpression(pattern: "\\[[^\\]]*\\]\\(\\s*([^)\\s]+)[^)]*\\)") {
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
        return UICollectionViewCompositionalLayout(sectionProvider: { _, _ in
            let size = NSCollectionLayoutSize(widthDimension: .absolute(max(opt.itemSize.width, 1)),
                                              heightDimension: .absolute(max(opt.itemSize.height, 1)))
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

    /// 图片组自适应尺寸：宽度撑满可用宽度，高度 = 标题区 +（可选间距）+ 图片高 + 上下内边距。
    private func preferredSize() -> CGSize {
        let width = availableWidth()
        var height = option.itemSize.height + option.contentInset.top + option.contentInset.bottom
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
        onContentSizeChanged?(size)
    }

    // MARK: UICollectionViewDataSource

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        imageURLs.count
    }

    public func collectionView(_ collectionView: UICollectionView,
                               cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CarouselCell.reuseID,
                                                      for: indexPath) as! CarouselCell
        let url = imageURLs[indexPath.item]
        cell.configure(urlString: url, option: option) { [weak self] image in
            if let image = image { self?.loadedImages[url] = image }
        }
        return cell
    }

    // MARK: UICollectionViewDelegate

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let index = indexPath.item
        guard index < imageURLs.count else { return }

        // 外部优先处理。
        if let handled = onImageTapped?(self, index, imageURLs), handled { return }

        // 内置全屏预览：收集已加载成功的图片，定位到点击项。
        guard option.usesBuiltinPreview else { return }
        var images: [UIImage] = []
        var startIndex = 0
        for (i, url) in imageURLs.enumerated() {
            if let img = loadedImages[url] {
                if i == index { startIndex = images.count }
                images.append(img)
            }
        }
        guard !images.isEmpty else { return }
        ImagePreviewer.shared.present(images, startIndex: startIndex, from: self, allowsSwipe: true)
    }
}
