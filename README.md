# AKHelper

AKHelper 是一个用于《明日方舟》公开招募的 iOS 辅助工具。它通过摄像头识别游戏中的公招词条，并根据内置的公招数据匹配可能出现的干员组合，帮助快速判断词条价值。

## 主要功能

- 使用摄像头实时识别公开招募界面的 5 个词条
- 自动匹配单词条、双词条和三词条组合
- 展示可招募干员、星级和职业信息
- 对 4 星及以上、5 星、6 星保底组合进行醒目提示

## 安装说明

本项目生成的是 iOS IPA 安装包。由于它不是通过 App Store 分发，安装到 iPhone 或 iPad 时需要使用侧载工具。

可使用的侧载工具例如：

- [Sideloadly](https://sideloadly.io)

基本流程：

1. 下载Release页面中的 `AKHelper-ios-unsigned.ipa`。
2. 在电脑上安装并打开 Sideloadly。
3. 将 iPhone 或 iPad 连接到电脑。
4. 在 Sideloadly 中选择 IPA 文件，并按照工具提示完成签名和安装。
5. 首次打开应用时，如果系统要求信任开发者证书，请在 iOS 设置中完成信任操作。

安装后，应用需要摄像头权限才能识别公招词条。

## 从源码构建

需要 macOS 和 Xcode。打开 `AKHelper/AKHelper.xcodeproj` 后，选择 `AKHelper` scheme，即可在真机或模拟器中构建运行。

## 数据说明

当前内置公开招募数据位于 `AKHelper/AKHelper/recruitment.json`，面向国服数据。
