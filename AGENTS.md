# Lysay 项目说明卡

## 项目简介

Lysay 是一款 iOS 第三方输入法，主打 **AI 语音输入**：边说边出字，每句话说完后用本地大模型精修（加标点、纠错、去语气词），目标是接近千问语音输入法的效果。全部识别在手机上离线完成。

- 语音输出默认繁体（台湾正体），键盘上可切换简体
- 打字用大千排列注音键盘（ㄅㄆㄇㄈ，词库来自小麦注音 McBopomofo，MIT），另有英文、数字、符号布局
- 粘贴板：在主 App 保存常用内容，键盘里点一下输入
- 设计风格贴近 iOS 原生，iOS 26 使用液态玻璃（`glassEffect`），旧系统退回毛玻璃
- 使用者自行用证书签名工具重签 IPA 安装到手机测试

## 技术架构

两段式离线识别（sherpa-onnx 1.13.8，`SherpaOnnxC.xcframework`，onnxruntime 静态链接）：

1. **流式**：阿里 Paraformer 中英双语流式模型 int8（`Resources/Models/streaming/`），实时出字 + 端点检测（停顿 0.8 秒算一句）
2. **精修**：Qwen3-ASR-0.6B int8（`Resources/Models/qwen3/`），整句重新识别，自带标点

**iOS 限制**：键盘扩展不能用麦克风。录音和识别都在主 App；键盘第一次按麦克风时用 `lysay://dictate` 跳到主 App 开麦，用户点左上角“◀ 返回”回原应用，键盘自动开始听写。主 App 靠 `UIBackgroundModes=audio` 在后台持续录音（默认保持 5 分钟）。

**通信**：主 App 在 `127.0.0.1:47821` 开 TCP 服务（`Engine/LocalServer.swift`），键盘连接后收发每行一个 JSON（`Shared/LysayIPC.swift`）。**不使用 App Group**，因为重签名后 App Group 往往失效。键盘需开启“允许完全访问”才能连本机网络。

## 主要目录

| 路径 | 内容 |
| --- | --- |
| `Lysay/` | 主 App（SwiftUI）：首页（开始使用教学 + 粘贴板入口 + 版本）、`ClipboardView`、键盘跳转引导页、`AppCoordinator` 总调度 |
| `LysayKeyboard/` | 键盘扩展：`KeyboardViewController`、`KeyboardModel`（上屏逻辑）、`KeyboardView`（界面）、`IPCClient`、`ZhuyinEngine` / `ZhuyinDictionary`（注音） |
| `Engine/` | 仅主 App：`SpeechEngine`（两段式识别）、`Recognizers`（sherpa-onnx 封装）、`AudioCapture`、`LocalServer`、`ChineseConverter`（OpenCC）、`TextPostProcessor`（去语气词）、`AppSettings` |
| `Shared/` | 两个 target 共用：通信协议、液态玻璃样式、麦克风圆球、`ClipStore`（粘贴板存取） |
| `Vendor/SherpaOnnx.swift` | sherpa-onnx 官方 Swift 封装（v1.13.8，开头加了 `import SherpaOnnxC`） |
| `Resources/OpenCC/` | OpenCC 繁简词库（已提交） |
| `Resources/Zhuyin/` | 注音词库 `zhuyin.txt`（由 `scripts/build_zhuyin_dict.py` 从 McBopomofo data.txt 生成，已提交） |
| `scripts/make_icon.py` | 生成 App 图标（黑底 LY 连笔 + 声波） |
| `Resources/Models/`、`Frameworks/` | 构建时由 CI 下载，不提交 |
| `project.yml` | XcodeGen 工程定义 |
| `.github/workflows/build-ipa.yml` | macOS 26 云端构建未签名 IPA，发布到 GitHub Release |

## 构建方式

Windows 无法编译 iOS。推送到 `main` 后，GitHub Actions（`macos-26`，Xcode 26.6）会：下载模型与框架 → `xcodegen generate` → `xcodebuild` 不签名构建 → 打包 `Lysay-1.0.<run>-unsigned.ipa` → 发布到仓库 Release（tag `build-<run>`）。

- 仓库：https://github.com/kack970209-eng/Lysay （公开）
- 本机 git 需加 `-c safe.directory=E:/Lysay`（E 盘不记录所有者）
- 提交前必须新增/修改 `接文档/` 交接文件，否则全局 pre-commit 钩子会拦截

## 目前状态

- 1.0.2 真机测试：语音功能正常
- 第 02 份交接加入注音键盘、新图标、精简首页、粘贴板，构建与真机测试结果见最新交接
- IPA 约 1.1GB（主要是 Qwen3 模型），Qwen3 运行时约占 1GB 内存
- 未实现：注音词频学习、长按地球键切换输入法列表

## 长期规则

- 构建产物给 IPA 下载链接，使用者手机自行签名安装（来源 01）
- 语音识别只用内置离线模型，不接云端（使用者选择“纯本地离线”，来源 01）
- 构建仓库用公开仓库（来源 01）
- 交接文件使用简体中文；必填栏位标题沿用钩子要求的“本機時間 / ## 目標 / ## 驗證 / ## 未解”
- 打字键盘要繁体注音（ㄅㄆㄇㄈ），不是简体/英文（来源 02）
- 图标：黑色底，LY 与语音结合成一体，不要对话气泡之类“AI 感”的图（来源 02）
- 主 App 首页只保留“开始使用”教学、粘贴板入口和版本信息；精修默认开启不给开关，不显示模型状态（来源 02）

## 查历史的方法

1. 先看本文件
2. 读 `HANDOVER.md` 的主题索引，找到相关编号
3. 只读那几份的摘要卡（前 10 行），确认相关再读全文
4. 索引查不到时，在 `接文档/` 用 grep 搜关键字
