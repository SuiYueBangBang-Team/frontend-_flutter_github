import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class VoiceIntentHandler {
  // 1. 保留原有的通用通道
  static const MethodChannel _channel = MethodChannel('voice_intent');

  // 💡 2. 新增：专门对接 Android 无障碍服务的通道 (需与原生端命名一致)
  static const MethodChannel _accessibilityChannel =
      MethodChannel('com.yourcompany.phone_java/accessibility');

  // 悬浮窗相关功能 (暂时禁用)
  /* 💡 3. 悬浮窗通道
  static const MethodChannel _floatChannel =
      MethodChannel('com.yourcompany.phone_java/float_window');
  */

  // // 注册悬浮窗长按回调（暂时禁用）
  // static void setFloatLongPressCallbacks({
  //   Function()? onStart,
  //   Function()? onEnd,
  // } ){}

  // 启动悬浮窗 (暂时禁用)
  /*
  static Future<void> showFloatWindow() async {
    try {
      await _floatChannel.invokeMethod('show');
    } catch (e) {
      print("显示悬浮窗失败: $e");
    }
  }
  */

  // 隐藏悬浮窗 (暂时禁用)
  /*
  static Future<void> hideFloatWindow() async {
    try {
      await _floatChannel.invokeMethod('hide');
    } catch (e) {
      print("隐藏悬浮窗失败: $e");
    }
  }
  */

  // 更新悬浮窗录制状态样式 (暂时禁用)
  /*
  static Future<void> updateFloatRecordingState(bool recording) async {
    try {
      await _floatChannel.invokeMethod('updateRecording', {'recording': recording});
    } catch (e) {
      print("更新悬浮窗录制状态失败: $e");
    }
  }
  */

  static final Map<String, Future<void> Function(Map<String, dynamic>)> _handlers = {
    'MEITUAN_SEARCH': _openMeituanSearch,
    'MEITUAN': _openMeituanHome,
    'WECHAT': _openWeChat,
    // 💡 3. 新增微信自动化动作
    'WECHAT_SCAN': _openWeChatScan,
    'WECHAT_VOICE_CALL': _startWeChatVoiceCall,
    'WECHAT_SEND_MESSAGE': _sendWeChatMessage,
    'OPEN_APP': _openAppByName,
    'SEARCH_IN_APP': _searchInApp, // 💡 新增应用内搜索支持
    // 💡 新增：高德地图导航
    'AMAP_NAVIGATE': _navigateWithAmap,
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
    // 检查是否有联系人参数：有的话走无障碍自动化拨打，没的话只打开微信
    final contact = (params['contact'] ?? params['contactName'] ?? params['keyword'] ?? '').toString().trim();
    if (contact.isNotEmpty) {
      print("📞 WECHAT action 带联系人参数: $contact，触发微信语音自动拨打");
      await _startWeChatVoiceCall({'contact': contact});
      return;
    }
    print("📱 WECHAT action 无联系人参数，仅打开微信");
    await _launchAnyApp(['weixin://']);
  }

  // 微信扫一扫：原生写入任务并拉起微信，由 WeChatAutoService 无障碍点击首页「更多功能」→「扫一扫」
  static Future<void> _openWeChatScan(Map<String, dynamic> params) async {
    try {
      final ok = await _accessibilityChannel.invokeMethod<bool>('startWeChatScan');
      if (ok == true) return;
    } catch (e) {
      print('微信扫一扫无障碍触发失败: $e');
    }
    await _launchAnyApp(['weixin://dl/scan']);
  }

  // 💡 5. 核心：实现拨打微信语音电话
  static Future<void> _startWeChatVoiceCall(Map<String, dynamic> params) async {
    final contact = (params['contact'] ?? params['contactName'] ?? '').toString().trim();
    if (contact.isEmpty) return;
    try {
      await _accessibilityChannel.invokeMethod('startWeChatCall', {'contact': contact});
    } catch (e) {
      print("调用微信语音自动化失败: $e");
    }
  }

  static Future<void> _sendWeChatMessage(Map<String, dynamic> params) async {
    final contact = (params['contact'] ?? params['contactName'] ?? '').toString().trim();
    final message = (params['message'] ?? '').toString().trim();
    if (contact.isEmpty || message.isEmpty) {
      print('❌ WECHAT_SEND_MESSAGE 缺少参数: contact=$contact, message=$message');
      return;
    }
    print('💬 WECHAT_SEND_MESSAGE 触发: 给 $contact 发 "$message"');
    try {
      await _accessibilityChannel.invokeMethod('startWeChatSendMessage', {
        'contact': contact,
        'message': message,
      });
    } catch (e) {
      print('微信发消息自动化失败: $e');
    }
  }

  static Future<void> _openAppByName(Map<String, dynamic> params) async {
    final appName = (params['appName'] ?? params['name'] ?? '').toString().trim();
    if (appName.isEmpty) return;

    print("🔍 _openAppByName 被调用，appName = $appName");

    try {
      final result = await _channel.invokeMethod<bool>('openAppByName', {'appName': appName});
      print("📱 原生 openAppByName 返回: $result");
      if (result == true) return;
    } catch (e) {
      print("❌ 原生 openAppByName 异常: $e");
    }

    // 兜底：用 Deep Link / url_launcher 尝试
    final deepLinkMap = {
      '美团': ['imeituan://www.meituan.com/', 'market://details?id=com.sankuai.meituan'],
      '微信': ['weixin://'],
      '支付宝': ['alipay://'],
      '抖音': ['snssdk1128://'],
      '拼多多': ['pinduoduo://'],
      '淘宝': ['taobao://'],
      '京东': ['openapp.jdmoble://'],
      '高德地图': ['androidamap://', 'amap://'],
      '高德': ['androidamap://', 'amap://'],
      '高德导航': ['androidamap://', 'amap://'],
      '快手': ['kwai://'],
      '小红书': ['snsdk://'],
    };

    for (final entry in deepLinkMap.entries) {
      if (appName.contains(entry.key)) {
        for (final url in entry.value) {
          print("🔄 兜底尝试 Deep Link: $url");
          final launched = await _launchAnyApp([url]);
          if (launched) return;
        }
      }
    }

    // 最终兜底：尝试通过市场 URL 打开
    final encoded = Uri.encodeComponent(appName);
    print("🔄 最终兜底尝试搜索应用: $appName");
    await _launchAnyApp([
      'https://play.google.com/store/search?q=$encoded',
      'market://search?q=$encoded',
    ]);
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

  // 💡 新增：高德地图导航
  // params 包含：destination (必填，目的地名称或地址)、latitude/longitude (可选经纬度)
  static Future<void> _navigateWithAmap(Map<String, dynamic> params) async {
    final destination = (params['destination'] ?? params['addr'] ?? params['address'] ?? '').toString().trim();
    if (destination.isEmpty) {
      print('❌ AMAP_NAVIGATE 缺少目的地参数');
      return;
    }

    print('🗺️ 高德地图导航: $destination');

    // 尝试使用高德地图导航 URI Scheme
    // 高德地图支持直接通过 scheme 打开并导航
    // amapuri://route/plan/?dlat=&dlon=&dname=&dev=0&t=0
    final encodedName = Uri.encodeComponent(destination);

    // 方案1：直接导航（高德地图客户端）
    // 如果后端返回了经纬度优先用经纬度
    final lat = params['latitude'] ?? params['lat'];
    final lon = params['longitude'] ?? params['lon'];

    List<String> navUrls;

    if (lat != null && lon != null) {
      // 有经纬度：直接导航到坐标
      navUrls = [
        'amapuri://route/plan/?dlat=$lat&dlon=$lon&dname=$encodedName&dev=0&t=0',
        'androidamap://navi?sourceApplication=appname&poiname=$encodedName&lat=$lat&lon=$lon&dev=0',
      ];
    } else {
      // 无经纬度：用名称搜索导航（打开高德地图并搜索该地点）
      navUrls = [
        // 高德地图搜索 URL Scheme
        'androidamap://openNavi?sourceApplication=appname&keyword=$encodedName',
        'amapuri://keywordNavi?keyword=$encodedName',
        // 兜底：打开高德地图（让用户手动选择）
        'amap://openFeature?featureName=search&query=$encodedName',
      ];
    }

    bool launched = await _launchAnyApp(navUrls);

    if (!launched) {
      // 最终兜底：尝试直接打开高德地图 App
      print('🔄 高德地图导航链接失败，尝试直接打开高德地图');
      launched = await _launchAnyApp([
        'amap://',
        'androidamap://',
      ]);

      if (!launched) {
        print('❌ 高德地图未安装或无法打开');
        // 兜底：打开网页版高德
        await _launchAnyApp([
          'https://restapi.amap.com/v3/place/text?keywords=$encodedName&output=json',
        ]);
      }
    } else {
      print('✅ 高德地图导航已启动: $destination');
    }
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