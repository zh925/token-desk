# Token Desk

Token Desk 是一款面向 macOS 5 寸副屏的常驻 AI 用量看板，固定适配 1280×720 分辨率，用于展示时间、天气、AI 套餐额度及按 Token 计费数据。

## 项目目录

```text
token-desk/
├── TokenDesk.xcodeproj/
├── TokenDesk/
├── Packages/TokenDeskKit/
├── Config/
├── README.md
├── docs/
│   ├── PRD.md
│   └── BUILDING.md
└── prototype/
    └── index.html
```

## 查看原型

直接使用浏览器打开 `prototype/index.html`。原型为单文件 HTML，不依赖网络、构建工具或第三方资源。

原型逻辑画布固定为 1280×720，在其他浏览器尺寸中会自动等比缩放。

## 当前产品范围

- 时间、日期和天气
- AI 套餐额度与重置时间
- Token 输入、输出、缓存与费用统计
- 国内外多 Provider 数据切换，包括 GLM、Kimi、MiniMax、DeepSeek 等
- 个人账户与组织/团队账户
- CSV/JSON 历史用量导出
- 可配置的套餐、预算、余额和同步失败告警
- Core Location 天气定位与手工城市回退
- Wokyis M5 1280×720 非触控适配
- Mac App Store 沙箱与上架要求
- 一个统一的设置入口
- 老款 Macintosh 风格视觉语言

当前版本不包含 Agent 状态、窗口拖拽、桌面模拟、系统菜单复刻和隐私模式。

## 文档

- [产品需求文档（PRD）](docs/PRD.md)
- [技术栈与架构决策](docs/TECH_STACK.md)
- [编码规范](docs/CODING_STANDARDS.md)
- [MVP 开发计划与任务排布](docs/DEVELOPMENT_PLAN.md)
- [构建与安全基线](docs/BUILDING.md)
