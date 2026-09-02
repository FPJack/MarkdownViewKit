//
//  MarkdownMusicView.swift
//  MarkdownViewKit
//
//  Markdown 中 `[music:URL]` 的自定义占位视图：
//  简洁的横向条状卡片 —— 左侧音乐图标 + 中间标题/时间 + 右侧播放/暂停按钮。
//  与 `MarkdownVideoView` 一样实现 `ViewLoadable`，通过 `updateData(data:)` 接收 URL 字符串。
//

import UIKit
import AVFoundation

// MARK: - 配置

/// 音乐占位视图配置。
public struct MusicOption {
    /// 占位视图宽度（<=0 表示跟随宿主宽度）。
    public var maxWidth: CGFloat = 0
    /// 占位视图高度。
    public var height: CGFloat = 64
    /// 圆角。
    public var cornerRadius: CGFloat = 10
    /// 背景色。
    public var backgroundColor: UIColor = UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0)
    /// 边框色。
    public var borderColor: UIColor = UIColor(white: 0, alpha: 0.06)
    /// 图标颜色。
    public var iconColor: UIColor = .systemBlue
    /// 播放按钮颜色。
    public var playIconColor: UIColor = .systemBlue
    /// 标题颜色。
    public var titleColor: UIColor = .label
    /// 时间颜色。
    public var timeColor: UIColor = .secondaryLabel
    /// 标题字体。
    public var titleFont: UIFont = .systemFont(ofSize: 14, weight: .medium)
    /// 时间字体。
    public var timeFont: UIFont = .systemFont(ofSize: 12)

    public init() {}
}

// MARK: - 视图

/// 音乐占位视图：图标 + 标题 / 时间 + 播放按钮。
@available(iOS 13.0, *)
public final class MarkdownMusicView: UIView, ViewLoadable {

    // MARK: ViewLoadable

    public typealias ViewData = String

    public var data: String = ""

    public func updateData(data: String) {
        self.data = data
        musicURL = URL(string: data)
    }

    public func startStreaming(data: String, animation: Bool) {
        updateData(data: data)
    }

    public var onContentSizeChanged: ((CGSize) -> Void)?
    public var onStreamingFinished: (() -> Void)?

    // MARK: 对外属性

    /// 音乐 URL。变化时重置播放器。
    public var musicURL: URL? {
        didSet {
            guard musicURL != oldValue else { return }
            resetPlayer()
            titleLabel.text = title ?? musicURL?.lastPathComponent ?? "音频"
        }
    }

    /// 音乐标题（不传时用 URL 末段代替）。
    public var title: String? {
        didSet {
            guard title != oldValue else { return }
            titleLabel.text = title ?? musicURL?.lastPathComponent ?? "音频"
        }
    }

    /// 配置。
    public var configuration: MusicOption {
        didSet { applyConfiguration() }
    }

    /// 播放按钮点击回调（返回 true 表示外部已处理，内部不再触发默认播放行为）。
    public var onPlayTapped: ((MarkdownMusicView) -> Bool)?

    // MARK: 子视图

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.image = UIImage(systemName: "music.note")
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingMiddle
        return l
    }()

    private let timeLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = "00:00 / --:--"
        return l
    }()

    private let playButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.setImage(UIImage(systemName: "play.circle.fill",
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .regular)),
                   for: .normal)
        return b
    }()

    // MARK: 播放器

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var isPlaying = false {
        didSet { updatePlayIcon() }
    }

    // MARK: 初始化

    public required init() {
        self.configuration = MusicOption()
        super.init(frame: .zero)
        setup()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(timeLabel)
        addSubview(playButton)

        playButton.addTarget(self, action: #selector(onTapPlay), for: .touchUpInside)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            playButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 40),
            playButton.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: playButton.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),

            timeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            timeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
        ])

        applyConfiguration()
    }

    private func applyConfiguration() {
        backgroundColor = configuration.backgroundColor
        layer.cornerRadius = configuration.cornerRadius
        layer.borderWidth = 1
        layer.borderColor = configuration.borderColor.cgColor

        iconView.tintColor = configuration.iconColor
        playButton.tintColor = configuration.playIconColor
        titleLabel.font = configuration.titleFont
        titleLabel.textColor = configuration.titleColor
        timeLabel.font = configuration.timeFont
        timeLabel.textColor = configuration.timeColor

        onContentSizeChanged?(CGSize(width: max(configuration.maxWidth, bounds.width),
                                     height: configuration.height))
    }

    // MARK: 播放控制

    @objc private func onTapPlay() {
        if let handled = onPlayTapped?(self), handled { return }

        if player == nil { preparePlayerIfNeeded() }
        guard let player = player else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // 允许静音模式下也能播放。
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
        }
    }

    private func preparePlayerIfNeeded() {
        guard let url = musicURL else { return }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p

        // 播放完成回到起点。
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onPlayEnd),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: item)
        // 每 0.5s 刷新一次时间显示。
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main) { [weak self] time in
                self?.updateTimeText(current: time.seconds,
                                     total: item.duration.seconds)
            }
    }

    @objc private func onPlayEnd() {
        player?.seek(to: .zero)
        isPlaying = false
    }

    private func resetPlayer() {
        player?.pause()
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        timeObserver = nil
        NotificationCenter.default.removeObserver(self,
                                                  name: .AVPlayerItemDidPlayToEndTime,
                                                  object: nil)
        player = nil
        isPlaying = false
        timeLabel.text = "00:00 / --:--"
    }

    private func updatePlayIcon() {
        let name = isPlaying ? "pause.circle.fill" : "play.circle.fill"
        playButton.setImage(UIImage(systemName: name,
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .regular)),
                            for: .normal)
    }

    private func updateTimeText(current: Double, total: Double) {
        func fmt(_ s: Double) -> String {
            guard s.isFinite, s >= 0 else { return "--:--" }
            let m = Int(s) / 60, sec = Int(s) % 60
            return String(format: "%02d:%02d", m, sec)
        }
        timeLabel.text = "\(fmt(current)) / \(fmt(total))"
    }

    // MARK: 生命周期

    public override func layoutSubviews() {
        super.layoutSubviews()
        onContentSizeChanged?(CGSize(width: bounds.width, height: configuration.height))
    }

    deinit {
        resetPlayer()
    }
}
