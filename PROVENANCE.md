# 来源核对记录

核对日期：2026-11-04。

用户已补充原“制作骇爪终端启动动画”对话截图：原开发说明将 HACKCLAW 工作台界面、交互、项目管理、图片输入和 Codex 连接代码列为该对话中逐步开发的部分；Windows 启动器另行参考并复用 Dragon Codex Boot。详细证据范围和边界见 CODE-ORIGINS.md。

此前“整个底座来源未知”的描述已被这条开发记录更新。这不是完整的 Git 历史或所有代码的独立相似性审计，不能把第三方组件和素材一起称为原创。

当前包的启动链：Start-EVA.cmd → start.ps1 → Node server.cjs → 官方 codex app-server；前端为网页、Canvas 和 Three.js。没有打包或调用原交接包的 DragonCodexBoot.cs/WPF 启动器、上游 MP4 或快捷方式替换工具。

Dragon Codex Boot：https://github.com/yushua0808-cpu/dragon-codex-boot 。2026-11-04 核对上游为 MIT，许可证全文在 licenses/DragonCodexBoot-MIT.txt。保留参考来源和许可，不自动将其用于整个工作台。

后续若找到其他明确复用代码，应补充相应许可。2026-11-05 所有者已选择自有代码采用 MIT，署名 Iris-change。完整私人视觉未公开分发，公开版使用占位素材；见 LICENSE-STATUS.md 和 ASSETS.md。
