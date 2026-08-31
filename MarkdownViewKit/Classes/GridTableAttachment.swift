//
//  GridTableAttachment.swift
//  StreamingTextView
//
//  一个「块级」流式文本附件：在富文本里为表格预留空间（占位空白，不绘制内容），
//  真正的 `GridTableView` 作为覆盖视图叠加在占位区域上方。配合 `StreamingTextView`：
//  当文字流式打印到该附件时会暂停文字，先让表格逐行流式打印，表格打印完成后再继续打印
//  后面的文字。
//
//  高度同步：附件初始高度为 0，表格每揭示一行、其内容尺寸变化时，附件会把 `bounds`
//  更新为表格「当前可见部分」的尺寸，并通过 `onLayoutChange` 通知宿主重新排版，
//  使 textView 的高度与表格高度**同步逐行增长**（而不是一开始就撑满整表高度）。
//

import UIKit

@available(iOS 13.0, *)
public class GridTableAttachment: BaseAttachment {
    
    public override var view: UIView? {
            get {
                return customView
            }
            set {
                super.view = newValue
            }
    }
    
    public var customView: GridTableView? = {
        let table = GridTableView()
        table.backgroundColor = .clear
        table.clipsToBounds = true
        return table
    }()

    /// 表格数据（二维单元格模型）。
    public let rows: [[GridCellModel]]
    /// 表格配置。
    public var configuration: GridTableOptions
    /// 逐行流式打印时每行出现的时间间隔（秒）。
    public var rowInterval: TimeInterval = 0.12

    /// 表格完整尺寸（全部行显示时），用于非动画一次性展示。
    private let fullSize: CGSize
   
    /// 尺寸变化时通知宿主重新排版的回调（由 `beginStreaming` 注入）。

    /// - Parameters:
    ///   - rows: 二维单元格模型。
    ///   - configuration: 表格配置（列宽 / 分割线 / 边框 / 滑动模式等）。
    public init(rows: [[GridCellModel]], configuration: GridTableOptions) {
        self.rows = rows
        self.configuration = configuration
        self.fullSize = GridTableView.calculateFittingSize(for: rows, configuration: configuration)
        super.init(data: nil, ofType: nil)
        // 初始高度为 0（宽度按完整宽度预留），随表格逐行流式增长。
        self.bounds = CGRect(x: 0, y: 0, width: 0, height: 0)
        self.image = UIImage(named: "image")
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
        completion: @escaping () -> Void) {
        guard let customView = customView else {
            return
        }
//        if frame.equalTo(customView.frame) {
//            return
//        }
        hostView.addSubview(customView)
       
        // 表格内容尺寸变化时（逐行增高）：同步更新附件 bounds 并请求宿主重新排版。
        // 附件 bounds 变化后，宿主会 invalidate 布局并通过 `updateFrame` 把表格 frame
        // 更新为新的尺寸与位置，实现 textView 高度与表格高度同步增长。
        customView.onContentSizeChanged = { [weak self] size in
            guard let self = self else { return }
            self.bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            onLayoutChange(self)
        }

        if animated {
            // 初始摆放在占位起点（高度 0），随逐行回调增长。
            customView.frame = CGRect(x: frame.origin.x, y: frame.origin.y, width: fullSize.width, height: 1)
            customView.onRowStreamingFinished = completion
            customView.setRows(rows, configuration: configuration)
            customView.startRowStreaming(rowInterval: rowInterval, animated: true)
        } else {
            // 非动画：一次性显示完整表格。
            bounds = CGRect(origin: .zero, size: fullSize)
            customView.frame = CGRect(origin: frame.origin, size: fullSize)
            customView.setRows(rows, configuration: configuration)
            completion()
        }
    }
    public override func updateViewFrame(_ frame: CGRect, in hostView: UIView) {
        super.updateViewFrame(frame, in: hostView)
        if frame.equalTo(customView?.frame ?? .zero) {
            return
        }
    }
    
    public override func removeView() {
        super.removeView()
        guard let customView = customView else {
            return
        }
        customView.onContentSizeChanged = nil
        customView.removeFromSuperview()
        self.customView = nil
        onLayoutChange = nil
    }
}
