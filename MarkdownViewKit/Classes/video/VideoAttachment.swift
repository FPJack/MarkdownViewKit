//
//  VideoAttachment.swift
//  MarkdownViewKit
//
//  一个「块级」流式文本附件：在富文本里为视频占位，
//  真正的视频占位视图（`MarkdownVideoView`）作为覆盖视图叠加在占位区域上方。
//  用法参考 `GridTableAttachment` / `GridTableView`。
//

import UIKit

@available(iOS 13.0, *)
public class VideoAttachment: BaseAttachment<MarkdownVideoView> {
    /// 视频 URL。
    public var urlString: String {
        didSet {
            guard urlString != oldValue else { return }
//            view?.videoURL = URL(string: urlString)
            view?.updateData(data: urlString)
        }
    }

    /// 视频标题（可选，叠加显示在视频占位左下角）。
    public var title: String? {
        didSet {
            guard title != oldValue else { return }
            view?.title = title
        }
    }

    /// 配置。
    public var configuration: VideoOption {
        didSet { view?.configuration = configuration }
    }

    /// 用于外部拦截默认播放行为。
    public var onPlayTapped: ((MarkdownVideoView) -> Bool)? {
        didSet { view?.onPlayTapped = onPlayTapped }
    }

    /// 用于自定义弹出播放器的宿主 VC 提供者。
    public var presenterProvider: (() -> UIViewController?)? {
        didSet { view?.presenterProvider = presenterProvider }
    }

    
    private func configureCustomView() {
        view?.configuration = configuration
        view?.videoURL = URL(string: urlString)
        view?.title = title
        view?.onPlayTapped = onPlayTapped
        view?.presenterProvider = presenterProvider
    }

    public init(urlString: String,
                title: String? = nil,
                configuration: VideoOption = VideoOption()) {
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
        configureCustomView()
        hostView.addSubview(customView)

        // 计算可用宽度：优先 configuration.maxWidth；否则用 TextKit 给的 frame.width；
        // 再兜底到宿主 textView 的宽度（TextKit 首次布局时 frame.width 可能为 0）。
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
        let height = max(available * configuration.aspectRatio, 60)

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

        // 首次就通知宿主重排一次，让 TextKit 用新的 bounds 撑出正确高度。
        onLayoutChange(self)
        customView.updateData(data: urlString)
        completion()
    }

    public override func updateViewFrame(_ frame: CGRect, in hostView: UIView) {
        super.updateViewFrame(frame, in: hostView)
    }

    public override func removeView() {
        super.removeView()
        guard let customView = view else { return }
        customView.onContentSizeChanged = nil
        customView.removeFromSuperview()
        self.view = nil
        onLayoutChange = nil
    }
}
