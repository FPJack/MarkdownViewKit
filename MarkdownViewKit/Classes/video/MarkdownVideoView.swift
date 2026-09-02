//
//  MarkdownVideoView.swift
//  MarkdownViewKit
//
//  一个视频占位视图：显示封面 + 播放按钮，点击后用系统 AVPlayerViewController 播放。
//  被 VideoAttachment 使用（对齐 GridTableAttachment / GridTableView 的关系）。
//

import UIKit
import AVKit
import AVFoundation

// MARK: - 配置

/// 视频占位视图配置。
public struct VideoOption {
    /// 占位视图宽（<=0 表示跟随宿主宽度）。
    public var maxWidth: CGFloat = 0
    /// 高度 = 宽度 × aspectRatio。
    public var aspectRatio: CGFloat = 9.0 / 16.0
    /// 圆角。
    public var cornerRadius: CGFloat = 8
    /// 背景色。
    public var backgroundColor: UIColor = UIColor(white: 0.1, alpha: 1.0)
    /// 边框色。
    public var borderColor: UIColor = UIColor(white: 0, alpha: 0.06)
    /// 播放按钮颜色。
    public var playIconColor: UIColor = UIColor.white
    /// 是否自动尝试用视频首帧作为封面（本地文件 & 远程视频均支持）。
    public var autoGenerateCover: Bool = true
    /// 显式指定的封面图 URL（优先于自动生成）。
    public var coverImageURL: URL?
    /// 标题文字颜色。
    public var titleColor: UIColor = .white
    /// 标题字号。
    public var titleFont: UIFont = .systemFont(ofSize: 13, weight: .medium)

    public init() {}
}

// MARK: - 视图

/// 视频占位视图：显示封面 + 播放按钮 + 可选标题。
@available(iOS 13.0, *)
public final class MarkdownVideoView: UIView {

    /// 视频 URL。setter 会重置封面并异步取首帧。
    public var videoURL: URL? {
        didSet {
            // 相同 URL 不重复触发（避免流式追加导致封面反复重取）。
            guard videoURL != oldValue else { return }
            coverTask?.cancel()
            coverTask = nil
            coverImageView.image = nil
            if configuration.autoGenerateCover {
                generateCoverIfNeeded()
            }
        }
    }

    /// 视频标题（叠加在底部）。
    public var title: String? {
        didSet {
            guard title != oldValue else { return }
            titleLabel.text = title
            titleLabel.isHidden = (title?.isEmpty ?? true)
        }
    }

    /// 播放触发回调（外部可拦截；返回 true 表示已自行处理，内部不弹播放器）。
    public var onPlayTapped: ((MarkdownVideoView) -> Bool)?

    /// 用于弹出播放器的宿主 VC 提供者（若不提供，会自动向上查找 `parentViewController`）。
    public var presenterProvider: (() -> UIViewController?)?

    /// 尺寸变化回调。
    public var onContentSizeChanged: ((CGSize) -> Void)?

    /// 配置。
    public var configuration: VideoOption {
        didSet { applyConfiguration() }
    }

    // MARK: 子视图

    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.backgroundColor = .clear
        return iv
    }()

    private let dimView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        return v
    }()

    private let playButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        b.layer.cornerRadius = 30
        b.tintColor = .white
        let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
        b.setImage(UIImage(systemName: "play.fill", withConfiguration: cfg), for: .normal)
        b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 8)
        return b
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.numberOfLines = 2
        l.isHidden = true
        return l
    }()

    private let titleGradient: CAGradientLayer = {
        let g = CAGradientLayer()
        g.colors = [UIColor.clear.cgColor,
                    UIColor.black.withAlphaComponent(0.65).cgColor]
        g.startPoint = CGPoint(x: 0.5, y: 0)
        g.endPoint = CGPoint(x: 0.5, y: 1)
        return g
    }()

    private let loading: UIActivityIndicatorView = {
        let v = UIActivityIndicatorView(style: .medium)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.hidesWhenStopped = true
        v.color = .white
        return v
    }()

    /// 首帧生成任务，用于取消。
    private var coverTask: DispatchWorkItem?

    /// 专用后台队列，避免占用共享 `.userInitiated` 全局队列，进而拖慢 WebView 等其它并发任务。
    private static let coverQueue = DispatchQueue(label: "MarkdownVideoView.coverQueue",
                                                  qos: .utility,
                                                  attributes: .concurrent)

    // MARK: 初始化

    public init(configuration: VideoOption = VideoOption()) {
        self.configuration = configuration
        super.init(frame: .zero)
        setup()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        // 注意：不要设 translatesAutoresizingMaskIntoConstraints = false，
        // 本视图由 VideoAttachment 直接用 frame 摆位；置为 false 后 AutoLayout
        // 会忽略手动 frame，把整个视图按内部约束的最小可满足值收缩成 (24, 0)。
        clipsToBounds = true

        addSubview(coverImageView)
        addSubview(dimView)
        layer.addSublayer(titleGradient)
        addSubview(titleLabel)
        addSubview(playButton)
        addSubview(loading)

        NSLayoutConstraint.activate([
            coverImageView.topAnchor.constraint(equalTo: topAnchor),
            coverImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            coverImageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            dimView.topAnchor.constraint(equalTo: topAnchor),
            dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: bottomAnchor),

            playButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 60),
            playButton.heightAnchor.constraint(equalToConstant: 60),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            loading.centerXAnchor.constraint(equalTo: centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        playButton.addTarget(self, action: #selector(handleTapPlay), for: .touchUpInside)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapPlay))
        addGestureRecognizer(tap)

        applyConfiguration()
    }

    private func applyConfiguration() {
        backgroundColor = configuration.backgroundColor
        layer.cornerRadius = configuration.cornerRadius
        layer.borderWidth = 1
        layer.borderColor = configuration.borderColor.cgColor
        playButton.tintColor = configuration.playIconColor
        titleLabel.textColor = configuration.titleColor
        titleLabel.font = configuration.titleFont
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // 标题底部渐变随尺寸变化。
        let h: CGFloat = 60
        titleGradient.frame = CGRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
        titleGradient.isHidden = titleLabel.isHidden
    }

    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        // 离屏时取消封面任务，防止后台线程还在跑 AVFoundation / Data(contentsOf:)。
        if newWindow == nil {
            coverTask?.cancel()
            coverTask = nil
            loading.stopAnimating()
        }
    }

    deinit {
        coverTask?.cancel()
    }

    // MARK: 首帧封面

    /// 允许 AVAssetImageGenerator 尝试的 URL scheme + 后缀过滤，防止把明显不是视频的
    /// URL 也丢给 AVFoundation（远程无效 URL 会占用后台线程做很长时间的 TCP / HTTP 尝试）。
    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "m3u8", "mpg", "mpeg", "avi", "mkv", "webm", "ts"
    ]
    private static func isLikelyVideoURL(_ url: URL) -> Bool {
        return true
        // 本地文件一律尝试。
        if url.isFileURL { return true }
        // 远程：schema 得是 http/https；后缀在白名单里，或路径里显式含 m3u8 / video 等。
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return true }
        // 后缀为空 / 未知：为了避免长时间无效等待，默认不再尝试；
        // 调用方可以显式设置 configuration.coverImageURL 走图片下载路径。
        return false
    }

    private func generateCoverIfNeeded() {
        coverTask?.cancel()
        coverTask = nil

        // 1) 显式封面 URL 优先。
        if let url = configuration.coverImageURL {
            loadCoverImage(from: url)
            return
        }
        guard let url = videoURL else { return }
        // 2) 过滤明显不是视频的 URL，避免 AVFoundation 长时间挂在后台。
        guard MarkdownVideoView.isLikelyVideoURL(url) else { return }

        loading.startAnimating()

        // 用 async API + 异步 loadValues，兼容远程 mp4（moov 位置不定）和 HLS。
        let requestedURL = url
        let asset = AVURLAsset(url: url,
                               options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let keys = ["tracks", "duration"]
        asset.loadValuesAsynchronously(forKeys: keys) { [weak self] in
            guard let self = self else { return }
            // 属性加载失败直接放弃，不刷新 UI。
            var loadFailed = false
            for k in keys {
                var err: NSError?
                if asset.statusOfValue(forKey: k, error: &err) != .loaded {
                    #if DEBUG
                    print("[MarkdownVideoView] load key \(k) failed: \(String(describing: err))")
                    #endif
                    loadFailed = true
                    break
                }
            }
            if loadFailed {
                DispatchQueue.main.async {
                    guard self.videoURL == requestedURL else { return }
                    self.loading.stopAnimating()
                }
                return
            }

            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = .positiveInfinity
            gen.requestedTimeToleranceAfter = .positiveInfinity
            gen.maximumSize = CGSize(width: 1024, height: 1024)

            // 优先 0 秒；失败时再退到 0.1 秒。
            let times = [CMTime.zero, CMTime(seconds: 0.1, preferredTimescale: 600)]
                .map { NSValue(time: $0) }

            var delivered = false
            gen.generateCGImagesAsynchronously(forTimes: times) { [weak self] _, cg, _, result, error in
                guard let self = self else { return }
                if delivered { return }              // 只处理第一个成功的
                guard result == .succeeded, let cg = cg else {
                    #if DEBUG
                    if let error = error {
                        print("[MarkdownVideoView] generate frame failed: \(error)")
                    }
                    #endif
                    return
                }
                delivered = true
                let image = UIImage(cgImage: cg)
                DispatchQueue.main.async {
                    // URL 又变了 / 任务被取消 → 丢弃结果。
                    guard self.videoURL == requestedURL else { return }
                    if self.coverTask?.isCancelled ?? false { return }
                    self.loading.stopAnimating()
                    self.coverImageView.image = image
                    self.coverTask = nil
                }
            }
        }

        // 用一个 dummy task 承担「取消」责任（当 URL 又变了 / 视图离屏时可以 cancel）。
        let cancelToken = DispatchWorkItem { [weak self, weak asset] in
            asset?.cancelLoading()
            _ = self
        }
        coverTask = cancelToken
    }

    private func loadCoverImage(from url: URL) {
        loading.startAnimating()
        let task = DispatchWorkItem { [weak self] in
            let data = try? Data(contentsOf: url)
            let img = data.flatMap { UIImage(data: $0) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.coverTask?.isCancelled ?? true { return }
                self.loading.stopAnimating()
                if let img = img { self.coverImageView.image = img }
                self.coverTask = nil
            }
        }
        coverTask = task
        MarkdownVideoView.coverQueue.async(execute: task)
    }

    // MARK: 播放

    @objc private func handleTapPlay() {
        guard let url = videoURL else { return }
        if let cb = onPlayTapped, cb(self) { return }
        let presenter = presenterProvider?() ?? parentViewController
        guard let presenter = presenter else { return }
        let player = AVPlayer(url: url)
        let vc = AVPlayerViewController()
        vc.player = player
        presenter.present(vc, animated: true) {
            player.play()
        }
    }
}

// MARK: - UIView 找 VC

private extension UIView {
    var parentViewController: UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }
}
