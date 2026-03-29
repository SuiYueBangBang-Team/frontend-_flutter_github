import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class VoiceIntentHandler {
  // 1. 保留原有的通用通道
  static const MethodChannel _channel = MethodChannel('voice_intent');

  // 💡 2. 新增：专门对接 Android 无障碍服务的通道 (需与原生端命名一致)
  static const MethodChannel _accessibilityChannel =
  MethodChannel('com.yourcompany.phone_java/accessibility');

  static final Map<String, Future<void> Function(Map<String, dynamic>)> _handlers = {
    'MEITUAN_SEARCH': _openMeituanSearch,
    'MEITUAN': _openMeituanHome,
    'WECHAT': _openWeChat,
    // 💡 3. 新增微信自动化动作
    'WECHAT_SCAN': _openWeChatScan,
    'WECHAT_VOICE_CALL': _startWeChatVoiceCall,
    'OPEN_APP': _openAppByName,
    'SEARCH_IN_APP': _searchInApp, // 💡 新增应用内搜索支持
  };

  static Future<void> handle({String? action, Map<String, dynamic>? params}) async {
    if (action == null) return;
    final handler = _handlers[action];
    if (handler == null) return;
    await handler(params ?? {});
  }

  // --- 处理函数实现 ---

  static Future<void> _openMeituanSearch(Map<String, dynamic> params) async {
    final keyword = (params['keyword'] ?? '').toString().trim();
    if (keyword.isEmpty) return;
    final encoded = Uri.encodeComponent(keyword);
    await _launchAnyApp([
      'imeituan://www.meituan.com/search/result?keyword=$encoded',
      'imeituan://www.meituan.com/',
    ]);
  }

  static Future<void> _openMeituanHome(Map<String, dynamic> params) async {
    await _launchAnyApp(['imeituan://www.meituan.com/']);
  }

  static Future<void> _openWeChat(Map<String, dynamic> params) async {
    await _launchAnyApp(['weixin://']);
  }

  // 💡 4. 实现微信扫一扫 (通过深链接)
  static Future<void> _openWeChatScan(Map<String, dynamic> params) async {
    await _launchAnyApp(['weixin://dl/scan']);
  }

  // 💡 5. 核心：实现拨打微信语音电话
  static Future<void> _startWeChatVoiceCall(Map<String, dynamic> params) async {
    // 提取联系人姓名 (如：妈妈、儿子)
    final contact = (params['contact'] ?? params['contactName'] ?? '').toString().trim();
    if (contact.isEmpty) return;

    try {
      // 通过无障碍通道调用 Android 原生代码，原生端会负责缓存联系人并唤起微信
      await _accessibilityChannel.invokeMethod('startWeChatCall', {'contact': contact});
    } catch (e) {
      print("调用微信语音自动化失败: $e");
    }
  }

  static Future<void> _openAppByName(Map<String, dynamic> params) async {
    final appName = (params['appName'] ?? params['name'] ?? '').toString().trim();
    if (appName.isEmpty) return;
    try {
      await _channel.invokeMethod('openAppByName', {'appName': appName});
    } catch (_) {}
  }

  // 💡 6. 实现通用应用内搜索 (如：在美团里搜索...)
  static Future<void> _searchInApp(Map<String, dynamic> params) async {
    final appName = (params['appName'] ?? params['app_name'] ?? '').toString().trim().toLowerCase();
    final keyword = (params['keyword'] ?? '').toString().trim();
    if (appName.isEmpty || keyword.isEmpty) return;

    if (appName.contains('美团') || appName.contains('meituan')) {
      await _openMeituanSearch({'keyword': keyword});
      return;
    }
    // 兜底：若不支持深链接搜索，则仅打开 App
    await _openAppByName({'appName': params['appName'] ?? params['app_name']});
  }

  static Future<bool> _launchAnyApp(List<String> urls) async {
    for (final urlString in urls) {
      final uri = Uri.parse(urlString);
      try {
        if (await canLaunchUrl(uri)) {
          final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (launched) return true;
        }
      } catch (_) {}
    }
    return false;
  }
}