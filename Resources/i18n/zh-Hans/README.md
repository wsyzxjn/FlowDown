# 浮望 (FlowDown)

<p align="center">
  <a href="../../../README.md">English</a> |
  <a href="/Resources/i18n/zh-Hans/README.md">简体中文</a>
</p>

浮望 (FlowDown) 是一款为 Apple 平台精心打造的原生 AI 对话客户端，追求极致的速度与流畅体验，并始终将你的隐私放在首位。无论是在 iPhone、iPad 还是 Mac 上，浮望都能为你提供与 AI 模型交互的绝佳体验。

![Preview](../../../Resources/SCR-PREVIEW.png)

## 下载

[![App Store Icon](../../../Resources/Download_on_the_App_Store_Badge_US-UK_RGB_blk_092917.svg)](https://apps.apple.com/us/app/flowdown-open-fast-ai/id6740553198)

**关于定价更新**

我们计划明年将浮望转为免费应用。随着更多开发者加入项目，核心功能日趋完善，维护需求相应减少，使我们能够以更低的成本提供服务（仅覆盖域名、托管、文档网站和开发者会员费等必要开支）。在完全免费之前，浮望将分阶段逐步降低价格。所有对话和聊天功能将保持免费；订阅费用仅适用于新增的个性化选项。

或加入 [TestFlight](https://testflight.apple.com/join/StpMeybv) 公开测试，抢先体验新功能。

为了让你能快速上手，浮望内置了免费的对话模型。我们鼓励你连接自托管的 OpenAI 兼容服务，以获得更强大、更稳定的体验。详情请查阅我们的[在线文档](https://apps.qaq.wiki/docs/flowdown/zh/)。

欢迎加入我们的 [Discord](https://discord.gg/UHKMRyJcgc) 社区，分享你的想法与建议。

## 特色功能

- **隐私至上**：你的对话历史和 API 密钥永远不会离开你的设备，所有数据都安全地存储在本地或通过你的私人 iCloud 同步。我们不收集任何用户数据。
- **原生性能**：浮望使用 Swift 倾力打造，轻盈且响应迅速。我们拒绝使用网页套壳技术，只为在 iOS 和 macOS 上提供无缝、流畅的原生体验。
- **广泛兼容**：你可以连接到任何兼容 OpenAI 的 API 服务，包括自托管的模型，让你拥有完全的自由和控制权。
- **绝佳体验**：完整的 Markdown 渲染、代码语法高亮，以及如丝般顺滑的交互界面，让与 AI 的每一次对话都成为享受。
- **强大工作流**：
  - **视觉模型**：与支持图像理解的多模态模型进行互动。
  - **音频支持**：使用附件向兼容的模型发送音频消息。
  - **文件附件**：在对话中轻松添加文件和文档。
  - **联网搜索**：授权 AI 访问互联网，获取实时信息。
  - **对话模板**：保存并快速复用你最喜欢的提示词。
  - **快捷指令**：与系统快捷指令深度集成，自动化你的工作流程。
- **iCloud 同步**：在你的所有 Apple 设备之间无缝同步对话、应用设置和自定义模型。
- **开源透明**：我们相信开源的力量。浮望采用 AGPL-3.0 许可证，欢迎你随时审查代码，共同见证我们对隐私和品质的承诺。

## 特别说明

浮望面向希望完全掌控 AI 模型配置、并愿意手动配置的用户。每个模型的表现因其能力、部署方式和硬件资源而异。你需要对自己配置和使用的每个模型负责。浮望提供工具和接口——配置由你负责。

如需批量管理，浮望支持导入和导出模型配置文件（`.fdmodel` 格式）。你可以编写脚本批量生成配置文件，然后一次性导入。欢迎加入我们的 [Discord](https://discord.gg/UHKMRyJcgc) 讨论配置方案，但请记住：社区建议不能替代你自己的测试验证。

## Star 历史

[![Star History Chart](https://api.star-history.com/svg?repos=Lakr233/FlowDown&type=date&legend=top-left)](https://www.star-history.com/#Lakr233/FlowDown&type=date&legend=top-left)

## 许可证

项目源代码基于 AGPL-3.0 许可证。你可以在 [LICENSE](../../../LICENSE) 文件中找到完整的许可证文本。

用于构建浮望或从中提取的解耦库如下，其各自许可证如下：

- [AlertController](https://github.com/Lakr233/AlertController) - MIT License
- [ColorfulX](https://github.com/Lakr233/ColorfulX) - MIT License
- [ListViewKit](https://github.com/Lakr233/ListViewKit) - MIT License
- [MarkdownView](https://github.com/Lakr233/MarkdownView) - MIT License
- [GlyphixTextFx](https://github.com/ktiays/GlyphixTextFx/) - MIT License

请注意，项目代码遵循开源许可，但“浮望”的名称、图标及相关视觉设计为专有资产。如需商业授权，请与我们联系。

---

© 2025 FlowDown 团队 (@Lakr233) 保留所有权利。
