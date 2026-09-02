//
//  MusicAttachment.swift
//  MarkdownViewKit
//
//  用于 `[music:URL]` 的块级附件：基于 `BaseAttachment<MarkdownMusicView>`。
//

import UIKit

@available(iOS 13.0, *)
public class MusicAttachment: BaseAttachment<MarkdownMusicView> {

    /// 音乐 URL 字符串。
    public var urlString: String {
        didSet {
            guard urlString != oldValue else { return }
            view?.updateData(data: urlString)
        }
    }

    /// 可选标题（不传时视图用 URL 末段兜底）。
    public var title: String? {
        didSet {
            guard title != oldValue else { return }
            view?.title = title
        }
    }

    /// 配置。
    public var configuration: MusicOption {
        didSet { view?.configuration = configuration }
    }

    /// 播放点击拦截回调。
    public var onPlayTapped: ((MarkdownMusicView) -> Bool)? {
        didSet { view?.onPlayTapped = onPlayTapped }
    }

    public init(urlString: String,
                title: String? = nil,
                configuration: MusicOption = MusicOption()) {
        self.urlString = urlString
        self.title = title
        self.configuration = configuration
        super.init(data: nil, ofType: nil)
        self.image = UIImage()
        self.bounds = CGRect(x: 0, y: 0, width: 0, height: 0)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - StreamingBlockAttachment

    public override func beginStreaming(
        in hostView: UIView,
        frame: CGRect,
        animated: Bool,
        onLayoutChange: @escaping (AttachmentLoadable) -> Void,
        completion: @escaping () -> Void
    ) {
        guard let customView = view else { completion(); return }
        // 先把视图内容同步到位。
        customView.configuration = configuration
        customView.title = title
        customView.updateData(data: urlString)

        hostView.addSubview(customView)

        // 计算宽度：优先 maxWidth；否则用占位区域宽度；再兜底到宿主宽度。
        var available = configuration.maxWidth > 0 ? configuration.maxWidth : frame.width
        if available <= 1 {
            if let tv = hostView as? UITextView {
                available = max(0, tv.bounds.width
                                - tv.textContainerInset.left
                                - tv.textContainerInset.right
                                - 2 * tv.textContainer.lineFragmentPadding)
            }
            if available <= 1 { available = hostView.bounds.width }
        }
        let height = configuration.height

        self.bounds = CGRect(x: 0, y: 0, width: available, height: height)
        customView.frame = CGRect(x: frame.origin.x, y: frame.origin.y,
                                  width: available, height: height)

        customView.onContentSizeChanged = { [weak self] size in
            guard let self = self else { return }
            let newBounds = CGRect(x: 0, y: 0, width: size.width, height: max(1, size.height))
            if newBounds.size != self.bounds.size {
                self.bounds = newBounds
                onLayoutChange(self)
            }
        }
        onLayoutChange(self)
        completion()
    }
}
