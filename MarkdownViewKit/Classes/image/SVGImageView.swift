//
//  SVGImageView.swift
//  MarkdownViewKit
//
//  原生（非 WebView）SVG 展示视图，遵循项目的 `ViewLoadable` 插件规则：
//    - `regxRule()` 匹配自定义语法 `[svg:URL]`（与 `[image:...]` 风格一致）；
//    - 也可承接标准 Markdown 图片 `![](x.svg)`（由 `RenderAttachment` 依据扩展名分流到本视图）；
//    - 通过 SDWebImage + 官方配套的 `SDWebImageSVGCoder` 把 SVG 解码成位图，
//      用 `UIImageView` 原生展示，不使用 WKWebView。
//
//  说明：iOS 的 CoreGraphics SVG 私有符号（CGSVGDocument*）既不在 .tbd 导出、
//  也无法通过 dlsym 运行时解析，所以自行 dlsym / extern 链接的方案都不可行；
//  这里改用生产环境验证过的 SDWebImageSVGCoder（内部已正确处理符号解析）。
//

import UIKit
import SDWebImage
import SDWebImageSVGCoder

// MARK: - SVGImageView

public class SVGImageView: UIImageView, ViewLoadable {

    /// 进程内只注册一次 SVG 解码器（SDWebImage 需要显式注册插件解码器）。
    private static let registerCoder: Void = {
        SDImageCodersManager.shared.addCoder(SDImageSVGCoder.shared)
    }()

    /// 图片显示的最大宽度（按比例缩放）。<=0 表示按 SVG 原始尺寸。
    public var maxImageWidth: CGFloat = 270

    /// 上一次已成功加载的资源标识，用于流式重复渲染时去重。
    private var lastLoadedSource: String?

    public static func regxRule() -> RegxRule {
        return RegxRule(pattern: "\\[svg:(.*?)\\]", options: .caseInsensitive)
    }

    public var onContentSizeChanged: ((CGSize) -> Void)?

    public var onStreamingFinished: (() -> Void)?

    public func updateData(data: TextMatch) {
        load(from: data)
    }

    public func startStreaming(data: TextMatch, animation: Bool) {
        load(from: data)
    }

    public func estimatedSize(for data: TextMatch) -> CGSize {
        let w = maxImageWidth > 0 ? maxImageWidth : 290
        return CGSize(width: w, height: 160)
    }

    // MARK: - 加载

    private func load(from data: TextMatch) {
        _ = Self.registerCoder

        let source = extractSource(from: data)
        guard !source.isEmpty, let url = URL(string: source) else {
            onStreamingFinished?()
            return
        }
        // 相同资源不重复渲染（流式追加时会多次触发）。
        if source == lastLoadedSource, image != nil {
            onStreamingFinished?()
            return
        }
        lastLoadedSource = source

        let maxWidth = maxImageWidth
        // 矢量图按目标像素尺寸栅格化，并保持宽高比。
        let pixel = maxWidth > 0 ? maxWidth * UIScreen.main.scale : 600
        let context: [SDWebImageContextOption: Any] = [
            .imageThumbnailPixelSize: CGSize(width: pixel, height: pixel),
            .imagePreserveAspectRatio: true
        ]

        SDWebImageManager.shared.loadImage(with: url, options: [], context: context, progress: nil) {
            [weak self] image, _, _, _, _, _ in
            guard let self = self else { return }
            guard self.lastLoadedSource == source else { return }
            guard let image = image else {
                self.onStreamingFinished?()
                return
            }
            self.image = image
            let w = maxWidth > 0 ? min(image.size.width, maxWidth) : image.size.width
            let h = image.size.width > 0
                ? image.size.height * (w / image.size.width)
                : image.size.height
            self.bounds = CGRect(x: 0, y: 0, width: floor(w), height: floor(h))
            self.onContentSizeChanged?(self.bounds.size)
            self.onStreamingFinished?()
        }
    }

    /// 从 `TextMatch` 中取出 SVG 资源标识：
    /// - `[svg:URL]` 自定义语法：去掉 `[svg:` 前缀与结尾 `]`；
    /// - 裸 URL（来自标准 Markdown 图片分流）：原样返回。
    private func extractSource(from data: TextMatch) -> String {
        let raw = data.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = raw.range(of: "^\\[svg:\\s*", options: [.regularExpression, .caseInsensitive]) {
            var s = String(raw[r.upperBound...])
            if s.hasSuffix("]") { s.removeLast() }
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw
    }
}
