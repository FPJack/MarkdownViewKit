# Markdown 全格式综合测试文档

### 块级公式1

$$E = mc^2$$


### 基础表格

| 姓名 | 年龄 | 职业 | 城市 |
| --- | ---: | :--- | :---: |
| Jack | 33 | iOS Developer | 深圳 |
| Tom | 28 | Android Developer | 北京 |
| Lucy | 30 | Designer | 上海 |

### Swift

```swift
import UIKit

func render(markdown: String) {
    markdownView.render(markdown)
}
```


```mermaid
flowchart LR
    A[开始] --> B[处理]
    B --> C[结束]
```

