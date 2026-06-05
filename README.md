# 每日任务汇总 App

一个原生 iPhone SwiftUI App，用文字、语音、图片输入事项，调用 GLM API 汇总成文字任务，并在每天固定时间通过本地通知提醒。通知里点击“完成”后，该任务不再提醒。

## 当前实现

- SwiftUI 单页聊天式输入界面
- 文字、录音、图片输入
- GLM API Key 存入 iOS Keychain
- `glm-asr-2512` 语音转文字
- `glm-5v-turbo` 汇总文字和图片内容
- 本地 JSON 保存任务
- 全局每日提醒时间设置
- iOS 本地通知动作：`完成`

## 使用前准备

1. 安装完整 Xcode。
2. 用 Xcode 打开 `DailyTaskVoiceApp.xcodeproj`。
3. 选择你的 Apple Team 和真机。
4. 第一次运行后进入设置，填写 GLM API Key。
5. 在 iPhone 设置中允许通知、麦克风和相册权限。

## 说明

- 当前仓库不包含任何 API Key。
- 任务和附件只保存在手机本地。
- 录音最长 60 秒；超过 30 秒会在本地分段转写后合并。

