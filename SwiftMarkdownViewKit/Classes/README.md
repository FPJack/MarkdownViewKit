# MarkdownKit

一个基于 [swift-markdown](https://github.com/swiftlang/swift-markdown) 的轻量、可复用的 Markdown → 富文本（`NSAttributedString`）渲染库，专为 UIKit 的 `UITextView` 展示而设计。

## 特性

- ✅ 标题、段落、粗体 / 斜体 / 删除线、行内代码
- ✅ 有序 / 无序列表、任务列表（`- [x]`）、多级缩进
- ✅ 代码块、引用块、分割线、表格
- ✅ 网络图片异步加载（内存缓存 + 按容器宽度等比缩放 + 自动刷新排版）
- ✅ 链接可点击
- ✅ 可扩展的自定义指令：行内 `[music:...]` / `[video:...]`，代码块 ```mermaid / ```echarts
- ✅ 主题化（字体 / 颜色 / 间距集中配置，一键换肤，自动适配明暗模式）

## 架构

采用分层 + 访问者模式，职责单一、易维护、易扩展：

```
MarkdownKit/
├─ Theme/        MarkdownStylerConfiguration / MarkdownStyler —— 样式配置 + 样式器（参考 Down）
├─ Core/         MarkdownParser           —— 对外统一入口（Facade）
├─ Rendering/    MarkdownAttributedStringBuilder —— 访问语法树生成富文本（MarkupVisitor）
├─ Directives/   MarkdownDirective        —— 自定义指令协议 + 注册表（开闭原则）
├─ Images/       AsyncImageTextAttachment —— 异步图片附件（下载 / 缓存 / 刷新）
└─ Views/        MarkdownTextView         —— 开箱即用的展示控件
```

## 快速使用

```swift
import UIKit

let textView = MarkdownTextView()
textView.markdown = "# Hello\n**世界** 你好"
// 或从 bundle 加载：
// textView.markdown = try? String(contentsOf: url, encoding: .utf8)
```

只要拿到 `NSAttributedString`：

```swift
let parser = MarkdownParser()
label.attributedText = parser.attributedString(from: markdownString)
```

## 自定义主题（样式配置，参考 Down 的方式）

样式体系分三层：**配置（Configuration）→ 样式器（Styler）→ 渲染器（Builder）**。

```
MarkdownStylerConfiguration (= MarkdownTheme)
   ├─ fonts:           MarkdownFontCollection            (StaticMarkdownFontCollection)
   ├─ colors:          MarkdownColorCollection           (StaticMarkdownColorCollection)
   ├─ paragraphStyles: MarkdownParagraphStyleCollection  (StaticMarkdownParagraphStyleCollection)
   ├─ listItemOptions / quoteStripeOptions / thematicBreakOptions
   └─ codeBlockOptions / imageOptions / tableOptions
        ↓
MarkdownStyler（DefaultMarkdownStyler，可继承覆写 style(...)）
        ↓
MarkdownAttributedStringBuilder（只负责遍历语法树）
```

### 1）改配置

```swift
var configuration = MarkdownStylerConfiguration()
configuration.fonts  = StaticMarkdownFontCollection(heading1: .boldSystemFont(ofSize: 30),
                                                    body: .systemFont(ofSize: 16),
                                                    code: .monospacedSystemFont(ofSize: 13, weight: .regular))
configuration.colors = StaticMarkdownColorCollection(body: .darkGray, link: .systemPink)
configuration.paragraphStyles = StaticMarkdownParagraphStyleCollection(lineSpacing: 6,
                                                                       paragraphSpacing: 14,
                                                                       headingSpacingBefore: 16)
configuration.listItemOptions      = MarkdownListItemOptions(nestedIndentation: 26)
configuration.quoteStripeOptions   = MarkdownQuoteStripeOptions(thickness: 3, spacingAfter: 10)
configuration.thematicBreakOptions = MarkdownThematicBreakOptions(repeatCount: 30)

markdownView.parser.theme = configuration          // 自动重建默认 styler
```

### 2）换样式器（更深度定制）

```swift
final class MyStyler: DefaultMarkdownStyler {
    override func style(heading str: NSMutableAttributedString, level: Int) {
        super.style(heading: str, level: level)
        if level == 1 { str.markdown_addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue) }
    }
}

markdownView.parser.styler = MyStyler(configuration: configuration)
```

### 3）旧写法依然可用

`MarkdownTheme` 现在就是 `MarkdownStylerConfiguration` 的别名，扁平属性会映射到新结构：

```swift
var theme = MarkdownTheme.default
theme.linkColor = .systemPink
theme.bodyFont  = .systemFont(ofSize: 16)
theme.lineSpacing = 6

let parser = MarkdownParser(theme: theme)
```

## 扩展自定义指令

```swift
struct MyDirective: InlineDirectiveRenderer {
    let name = "user"
    func render(payload: String, theme: MarkdownTheme) -> NSAttributedString {
        NSAttributedString(string: "@\(payload)",
                           attributes: [.foregroundColor: theme.linkColor])
    }
}

let registry = MarkdownDirectiveRegistry.default
registry.register(inline: MyDirective())      // 支持 [user:xxx]

let parser = MarkdownParser(directives: registry)
```

## 集成到其它项目

1. 将 `MarkdownKit/` 整个文件夹拖入你的工程；
2. 通过 SPM 添加依赖 `https://github.com/swiftlang/swift-markdown`（产品名 `Markdown`）；
3. 直接使用 `MarkdownTextView` 或 `MarkdownParser`。

## 依赖

- iOS 13+
- swift-markdown（`import Markdown`）
