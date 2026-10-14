# 浮译 · Hover Translate

原生 macOS 菜单栏翻译工具：英文悬停取词、局部 OCR、选区双向翻译，以及输入框内的译文预览与替换。

Native macOS hover and selection translator built with SwiftUI, AppKit, Vision, Accessibility and Apple Translation. Text and image recognition run locally; no third-party translation API or API key is required.

> 当前为 v0.3.1 预览版。跨应用取词、输入框替换与撤销的兼容性仍需逐应用验证。

## 功能

- **悬停翻译**：在英文上停留后出现小“译”图标，鼠标移入图标展开中文译文，无需选中或点击。
- **选区翻译**：选中文字直接打开统一浮窗，在「原文 / 中文 / EN」之间切换，可复制或固定译文。
- **输入框替换**：确认选区来自可安全编辑的输入框后，显示“替换选中文字”。先预览译文，点击后才替换选中的部分；成功后关闭浮窗并交回输入焦点，可尝试在原应用按 `⌘Z` 撤销。
- **局部 OCR**：对于无法直接读取的系统界面或图片，在获得屏幕录制权限后截取鼠标附近内容，使用 Vision 识别。
- **可调触发**：悬停等待 300–1500 ms，移开后的关闭等待 0–1000 ms。选区浮窗不因鼠标移开原文而自动关闭。
- **外观**：紧凑柔雾玻璃译文浮窗；绿色悬停图标随系统深浅外观自动调整明暗。

![可编辑选区浮窗样式](docs/images/selection-translation.png)

图中为使用示例文字渲染的原生界面样例，不包含真实用户内容。

## 系统与构建要求

- macOS 26 或更新版本。
- 较新的 Xcode / Command Line Tools，SDK 需要包含代码中使用的 macOS 26.4 Translation 低延迟接口。
- 当前构建验证环境：Apple Silicon、Swift 6.4、macOS 27 SDK。Intel 构建尚未验证。
- 中英文翻译语言包：首次使用在应用偏好设置中准备，由系统下载。
- 无第三方 Swift 包依赖。

## 从源码运行

```sh
git clone https://github.com/Kianzzz/hover-translate.git
cd hover-translate
zsh scripts/test.sh
zsh scripts/build-app.sh
open "$HOME/Applications/浮译.app"
```

构建脚本默认将应用安装到 `~/Applications/浮译.app`，构建缓存放在 `~/Library/Caches/HoverTranslate/build`。已有同名应用时，应先退出并自行备份；构建脚本会更新目标应用包。

可通过环境变量改为独立测试包，不影响已有安装：

```sh
HOVER_TRANSLATE_BUILD_DIR="$HOME/Library/Caches/HoverTranslate/public-build" HOVER_TRANSLATE_APP_DIR="$HOME/Library/Caches/HoverTranslate/public-test.bundle" zsh scripts/build-app.sh
```

临时包使用 `.bundle` 后缀，以减少测试包混入 LaunchServices 和系统授权列表的情况。实际运行请使用正常安装的 `.app`。

公开版默认 bundle ID 为 `io.github.kianzzz.hovertranslate`。自行分发时可修改 `Info.plist` 中的标识；不同标识、签名或安装路径可能需要独立授权。源码构建使用本机临时签名，未做 Developer ID 签名或公证。本仓库暂不提供预编译应用下载。

## 权限准备

开启全局翻译时，应用会引导至系统隐私权限页：

1. **设备控制与数据访问 / 辅助功能**：读取鼠标附近或选中的界面文字，核对可编辑输入框；仅在你点击替换后发送一次普通粘贴操作。请进入“隐私与安全性”下的授权页，而不是左侧通用“辅助功能”设置。
2. **屏幕录制**：为系统取词无法覆盖的内容启用局部 OCR。不启用时，可使用系统直接提供的文字。
3. **语言包**：在应用偏好设置中准备中英文语言包。

添加窗口找不到应用时，可使用应用内“复制应用路径”，在系统添加窗口按 `⇧⌘G` 粘贴路径，然后选择应用。系统要求退出并重新打开时，按提示操作；返回浮译后点击“重新检测”。

临时签名重新构建后，旧版本授权可能不再对新构建生效；应通过系统设置重新确认当前应用的授权。

## 使用方式

- 菜单栏可开启、暂停或退出全局翻译。关闭主窗口不会退出应用。
- 悬停英文 → 移入“译”图标 → 查看中文。默认等待 600 ms，默认移开后立即收起；固定浮窗除外。
- 选中文字 → 点击中文或 EN 查看译文。也可以用 `⌃⌥T`（Control + Option + T）打开选区浮窗。
- 可编辑输入框 → 确认译文 → 点击“替换选中文字”。原文页、翻译未完成、结果未变化或替换进行中，不允许提交替换。
- 替换后在原输入框按 `⌘Z`，使用原编辑器的撤销记录。是否能撤销取决于目标应用，尤其需要验证网页富文本编辑器。
- 输入框或选区已改变时拒绝旧替换，不会自动重新选中旧文字；无法确认替换结果时不重试，避免重复插入。
- 只读选区或无法确认安全编辑能力的输入框，浮窗只提供翻译与复制。
- 不支持直接取词的应用也可手动复制文字，再从菜单栏选择“翻译剪贴板”。

## 隐私与数据处理

- 应用自身不向第三方翻译服务上传文字或截图，不接入分析统计。
- 识别使用 Accessibility / Vision，翻译使用 Apple Translation；语言包准备可能需要联网下载。
- 不自动监视剪贴板。手动翻译剪贴板与复制译文均由用户触发。
- 点击替换时临时借用剪贴板，在目标应用消费粘贴后恢复；期间用户主动复制的新内容不会被覆盖。
- 翻译缓存与当前选区只留在进程内存，不记录翻译历史或持久化截图。设置通过 UserDefaults 保存。
- 受保护或密码输入框不会参与替换。

## 验证

```sh
zsh scripts/test.sh
"$HOME/Applications/浮译.app/Contents/MacOS/HoverTranslate" --check-hover-flow
"$HOME/Applications/浮译.app/Contents/MacOS/HoverTranslate" --check-engine
```

- `test.sh`：直接编译执行 28 项文本、坐标、浮窗尺寸与选区替换边界检查。
- `--check-hover-flow`：验证取词安全、悬停生命周期、选区浮窗保留、替换按钮状态和无效目标的剪贴板安全；不执行对真实输入框的替换。
- `--check-engine`：检查已安装的语言包，并在可用时执行真实中英双向翻译。
- `open "$HOME/Applications/浮译.app" --args --check-window-flow`：执行 12 轮原生窗口生命周期检查，交替检查带替换栏与只读模式，随后退出。运行前请退出正常实例。
- `--check-self-hit-flow`：针对自身 AX 命中的原生检查，需要当前安装已有有效辅助功能授权；运行前请退出正常实例。

手动输入框验证页位于 `scripts/selection-fixture.html`。用示例文字检查“选中 → 翻译 → 替换 → ⌘Z”，确认未选中的前后文字保持不变。自动检查不代表所有应用兼容性或撤销行为都已验证。

## 已知边界

- 部分应用不开放 Accessibility 文字、选区或安全编辑信息，因此无法直接取词或提供替换按钮。
- OCR 当前按鼠标所在行或词识别，尚未合并跨行完整句；细小、模糊或手写文字可能识别不准。
- 本机 OCR 使用英文快速识别及 CPU 处理路径，以降低模型初始化等待；中文选区主要依赖 Accessibility。
- 应用提供的选区边界可能不准确；屏幕边缘可能限制浮窗摆放。选区浮窗会保留至外部点击、滚动、继续输入或主动关闭。
- 当前语言组合面向简体中文与英文，未验证其他语言。
- 项目仅调用 macOS 公共框架；系统授权、语言包和目标应用行为不受本工具控制。

## 项目结构

```text
Sources/HoverTranslate/  原生界面、取词、翻译与安全替换
Tests/                  核心检查
scripts/                构建、检查、图标生成与示例页面
Assets/                 应用图标
docs/images/            仅含示例文字的界面图片
```

## 反馈与贡献

欢迎提交 Issue 或 Pull Request。复现时尽量使用“你好，世界！”等示例文字；不要公开未脱敏的聊天、文档、账号、密码、令牌或完整崩溃报告。请说明 macOS 版本、应用名称、复现步骤及预期行为。

## License

[MIT](LICENSE) © 2026 Kianzzz
