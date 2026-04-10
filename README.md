# 岁月帮帮

一个基于 Flutter 的“关怀模式 AI 助手”移动端项目。

## 功能概览

- 长按录音，上传音频到后端进行意图识别
- 输入文本进行指令测试
- 根据后端动作执行系统能力或外部 App 跳转
  - 微信分享文本
  - 支付宝扫一扫
  - 美团打开/搜索
  - 直接拨号
  - 拍照
- 支持 TTS 语音反馈播报

## 技术栈

- Flutter / Dart
- Dio（网络请求）
- record（录音）
- flutter_tts（语音播报）
- fluwx（微信能力）
- url_launcher（外部应用拉起）
- image_picker（拍照）
- flutter_phone_direct_caller（直接拨号）

## 后端接口约定

默认后端地址：`http://10.0.2.2:9000`

- `POST /api/ai/parse-intent`：文本意图解析
- `POST /api/ai/parse-audio`：音频意图解析

返回结构示例：

```json
{
  "action": "CALL",
  "params": {
    "phoneNumber": "10086"
  },
  "voiceFeedback": "好的，正在帮您拨打电话"
}
```

## 环境变量

支持使用 `.env` 覆盖默认配置（未配置时使用代码默认值）。

示例：

```env
AI_BASE_URL=http://10.0.2.2:9000
WECHAT_APP_ID=你的微信开放平台AppID
```

## 启动

```bash
flutter pub get
flutter run
```

## 注意事项

- `10.0.2.2` 仅适用于 Android 模拟器访问宿主机
- 真机调试请将 `AI_BASE_URL` 改为可访问地址
- 微信能力需在微信开放平台完成配置
