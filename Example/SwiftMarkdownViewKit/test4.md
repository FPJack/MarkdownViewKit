## 四、链接

### 行内链接

[GitHub](https://github.com)

[Apple 官网](https://www.apple.com)

[带标题的链接](https://www.google.com "这是链接标题")

### 自动链接

<https://github.com>

<https://www.apple.com>

<example@example.com>

裸 URL：https://www.swift.org

### 引用式链接

这是一个[引用式链接][ref1]，这是[另一个][ref2]。

这是一个[隐式引用式链接][]。

[ref1]: https://github.com "GitHub 首页"
[ref2]: https://www.apple.com
[隐式引用式链接]: https://www.swift.org

### 脚注

这里有一个脚注[^1]，这里还有一个[^note]。

[^1]: 这是第一个脚注的内容。
[^note]: 这是一个命名脚注的内容。

---

## 五、图片

### 行内图片

![山川风景](https://img2.baidu.com/it/u=2838910375,3102156952&fm=253&app=138&f=JPEG?w=800&h=1067)

### 带标题的图片

![产品图片](https://gips1.baidu.com/it/u=1658389554,617110073&fm=3028&app=3028&f=JPEG&fmt=auto?w=1280&h=960 "这是图片标题")

### SVG 徽章

![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)

![Platform](https://img.shields.io/badge/platform-iOS-lightgrey.svg)

### Base64 Data URI 图片

![绿色圆形](data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMDAiIGhlaWdodD0iMTAwIj48Y2lyY2xlIGN4PSI1MCIgY3k9IjUwIiByPSI0MCIgZmlsbD0iIzRjYWY1MCIvPjwvc3ZnPg==)

### 可点击的图片链接

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://www.swift.org)

### 图文混排

下面这段文字用于测试图片与文字的混排效果：

![山川风景](https://img2.baidu.com/it/u=2838910375,3102156952&fm=253&app=138&f=JPEG?w=800&h=1067)

图片展示了一幅美丽的自然风景，上下文字应当与图片保持合理间距。

---

## 六、引用

> 这是一个简单的引用。

> 这是一段比较长的引用文本，用于测试多行引用的显示效果。如果引用内容超过当前容器宽度，就应该自动换行。

> 这是一个多行引用。
>
> 第二行引用。
>
> 第三行引用。

### 嵌套引用

> 一级引用
>
> > 二级嵌套引用
> >
> > > 三级嵌套引用

### 引用中包含其他元素

> ### 引用中的标题
>
> 引用中的 **粗体**、*斜体* 和 `行内代码`。
>
> - 引用中的列表项一
> - 引用中的列表项二
>
> ```swift
> print("引用中的代码块")
> ```
>
> | 列 A | 列 B |
> | :--- | ---: |
> | 引用中的表格 | 123 |
