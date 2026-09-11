//
//  ViewLoadable.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/11.
//

import UIKit
public struct TextMatch{
    
}
public protocol ViewLoadable where Self: UIView{
    var viewOptions: ViewOption { get set }

    /// 视图尺寸变化时回调，通常用于通知宿主更新附件的占位尺寸。
    var onContentSizeChanged: ((CGSize) -> Void)? { get set }
    /// 流式加载完成时回调，通常用于通知宿主更新附件的占位尺寸。
    var onStreamingFinished: (() -> Void)? {get set}
    /// 更新视图数据（通常用于刷新视图内容）。
    func updateData(data: TextMatch)
    /// 开始流式加载数据（通常用于网络图片或视频）。
    func startStreaming(data: TextMatch,animation: Bool)
    /// 估算视图尺寸（通常用于计算附件的占位尺寸）。
    func estimatedSize(for data: TextMatch) -> CGSize
    /// 转换匹配结果（通常用于在渲染前对匹配结果进行处理或修改）。
    func convertTextMatch(_ markdownView: UIView,match: TextMatch) -> TextMatch
    /// 返回内容的内边距（通常用于调整视图内容与边界的间距）。
    func attachmentContentInset() -> UIEdgeInsets
}
extension ViewLoadable {
   public func attachmentContentInset() -> UIEdgeInsets {
        .init(top: 10, left: 10, bottom: 10, right: 10)
    }

}
