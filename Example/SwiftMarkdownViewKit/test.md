# SVG 图片测试

## 1. 内联 SVG（圆形 + 渐变）

<svg width="200" height="120" viewBox="0 0 200 120" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g1" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#4facfe"/>
      <stop offset="100%" stop-color="#00f2fe"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="200" height="120" rx="12" fill="url(#g1)"/>
  <circle cx="60" cy="60" r="35" fill="#ffffff" fill-opacity="0.85"/>
  <text x="110" y="66" font-size="16" fill="#ffffff">Inline SVG</text>
</svg>

## 2. 内联 SVG（折线图）

<svg width="240" height="140" viewBox="0 0 240 140" xmlns="http://www.w3.org/2000/svg">
  <rect width="240" height="140" fill="#fafafa" stroke="#e0e0e0"/>
  <polyline points="20,120 60,80 100,95 140,45 180,60 220,20"
            fill="none" stroke="#ef4136" stroke-width="3"/>
  <line x1="20" y1="120" x2="220" y2="120" stroke="#999" stroke-width="1"/>
  <line x1="20" y1="20" x2="20" y2="120" stroke="#999" stroke-width="1"/>
</svg>

## 3. 内联 SVG（星星图标）

<svg width="80" height="80" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path d="M12 2l2.9 6.3 6.9.8-5.1 4.7 1.4 6.8L12 17.3 5.9 20.6l1.4-6.8L2.2 9.1l6.9-.8z"
        fill="#FFC107" stroke="#F57C00" stroke-width="0.5"/>
</svg>

## 4. HTML img 引用远程 SVG

<img src="https://upload.wikimedia.org/wikipedia/commons/0/02/SVG_logo.svg" alt="SVG Logo" width="120">

## 5. Markdown 语法引用远程 SVG

![SVG Logo](https://upload.wikimedia.org/wikipedia/commons/0/02/SVG_logo.svg)

![Swift Shields](https://img.shields.io/badge/Swift-5.9-orange.svg)

## 6. Base64 Data URI 的 SVG

![Data URI SVG](data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMDAiIGhlaWdodD0iMTAwIj48Y2lyY2xlIGN4PSI1MCIgY3k9IjUwIiByPSI0MCIgZmlsbD0iIzRjYWY1MCIvPjwvc3ZnPg==)

行内也可以混排一个小图标 <svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg"><circle cx="8" cy="8" r="7" fill="#2196F3"/></svg> 这样。
