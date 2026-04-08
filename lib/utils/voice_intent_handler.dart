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
    // 💡 新增：拼多多搜索
    'PINDUODUO_SEARCH': _openPinduoduoSearch,
    'PINDUODU': _openPinduoduoHome,
    // 💡 微信内指定小程序：手机充值（原生 SDK 拉起，需配置 wechat.app.id）
    'WECHAT_PHONE_RECHARGE': _openWeChatPhoneRechargeMiniProgram,
  };

  static Future<void> handle({String? action, Map<String, dynamic>? params}) async {
    if (action == null) return;
    final handler = _handlers[action];
    if (handler == null) return;
    await handler(params ?? {});
  }

  // --- 处理函数实现 ---

  /// 拉起「手机充值」微信小程序（原始 ID gh_fefb88a96b0e，与后端 WECHAT_PHONE_RECHARGE 对应）
  static Future<void> _openWeChatPhoneRechargeMiniProgram(Map<String, dynamic> params) async {
    final path = (params['path'] ?? '').toString().trim();
    print('📱 WECHAT_PHONE_RECHARGE 触发，拉起微信小程序（手机充值）');
    try {
      final args = <String, dynamic>{};
      if (path.isNotEmpty) args['path'] = path;
      final ok = await _channel.invokeMethod<bool>('launchWeChatPhoneRechargeMiniProgram', args);
      if (ok == true) {
        print('✅ 已请求微信打开小程序');
        return;
      }
    } catch (e) {
      print('❌ 拉起微信小程序失败（请检查是否配置 android/gradle.properties 的 wechat.app.id）: $e');
    }
    await _launchAnyApp(['weixin://']);
  }

  static Future<void> _openMeituanSearch(Map<String, dynamic> params) async {
    final keyword = (params['keyword'] ?? '').toString().trim();
    if (keyword.isEmpty) {
      print('❌ MEITUAN_SEARCH 缺少关键词参数');
      return;
    }

    print('🍜 MEITUAN_SEARCH 触发，关键词: $keyword');

    // 方案1：优先通过原生无障碍服务（自动点击搜索框、输入关键词、点搜索）
    try {
      final result = await _accessibilityChannel.invokeMethod<bool>('startMeituanSearch', {
        'keyword': keyword,
      });
      if (result == true) {
        print('✅ 美团搜索已通过无障碍服务启动: $keyword');
        return;
      }
    } catch (e) {
      print('⚠️ 美团无障碍通道调用失败，回退到 Deep Link: $e');
    }

    // 方案2：Deep Link 兜底
    final encoded = Uri.encodeComponent(keyword);
    bool launched = await _launchAnyApp([
      'imeituan://www.meituan.com/search/result?keyword=$encoded',
      'imeituan://www.meituan.com/',
    ]);
    if (!launched) {
      print('❌ 美团未安装或无法打开');
    } else {
      print('✅ 美团搜索已通过 Deep Link 启动: $keyword');
    }
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
  // 策略：优先走原生无障碍通道（自动在高德地图搜索目的地），Deep Link 作为兜底
  static Future<void> _navigateWithAmap(Map<String, dynamic> params) async {
    final destination = (params['destination'] ?? params['addr'] ?? params['address'] ?? '').toString().trim();
    if (destination.isEmpty) {
      print('❌ AMAP_NAVIGATE 缺少目的地参数');
      return;
    }

    print('🗺️ 高德地图导航: $destination');

    // 方案1：优先通过原生无障碍服务启动高德地图并自动输入目的地
    try {
      final lat = params['latitude'] ?? params['lat'];
      final lon = params['longitude'] ?? params['lon'];
      final result = await _accessibilityChannel.invokeMethod<bool>('startAmapNavi', {
        'destination': destination,
        'latitude': lat,
        'longitude': lon,
      });
      if (result == true) {
        print('✅ 高德地图导航已通过无障碍服务启动: $destination');
        return;
      }
    } catch (e) {
      print('⚠️ 高德地图无障碍通道调用失败，回退到 Deep Link: $e');
    }

    // 方案2：Deep Link 兜底（高德地图客户端 URI Scheme）
    final encodedName = Uri.encodeComponent(destination);
    final lat = params['latitude'] ?? params['lat'];
    final lon = params['longitude'] ?? params['lon'];

    List<String> navUrls;

    if (lat != null && lon != null) {
      navUrls = [
        'amapuri://route/plan/?dlat=$lat&dlon=$lon&dname=$encodedName&dev=0&t=0',
        'androidamap://navi?sourceApplication=appname&poiname=$encodedName&lat=$lat&lon=$lon&dev=0',
      ];
    } else {
      navUrls = [
        'androidamap://openNavi?sourceApplication=appname&keyword=$encodedName',
        'amapuri://keywordNavi?keyword=$encodedName',
        'amap://openFeature?featureName=search&query=$encodedName',
      ];
    }

    bool launched = await _launchAnyApp(navUrls);

    if (!launched) {
      print('🔄 高德地图导航链接失败，尝试直接打开高德地图');
      launched = await _launchAnyApp(['amap://', 'androidamap://']);

      if (!launched) {
        print('❌ 高德地图未安装或无法打开');
      }
    } else {
      print('✅ 高德地图导航已通过 Deep Link 启动: $destination');
    }
  }

  // 拼多多搜索：优先通过原生无障碍通道，Deep Link 为兜底
  static Future<void> _openPinduoduoSearch(Map<String, dynamic> params) async {
    final keyword = (params['keyword'] ?? '').toString().trim();
    if (keyword.isEmpty) {
      print('❌ PINDUODUO_SEARCH 缺少关键词参数');
      return;
    }

    print('🛒 PINDUODUO_SEARCH 触发，关键词: $keyword');

    try {
      final result = await _accessibilityChannel.invokeMethod<bool>('startPinduoduoSearch', {
        'keyword': keyword,
      });
      if (result == true) {
        print('✅ 拼多多搜索已通过无障碍服务启动: $keyword');
        return;
      }
    } catch (e) {
      print('⚠️ 拼多多无障碍通道调用失败，回退到 Deep Link: $e');
    }

    final encoded = Uri.encodeComponent(keyword);
    bool launched = await _launchAnyApp([
      'pinduoduo://com.xunmeng.pinduoduo/search?keyword=$encoded',
      'pinduoduo://',
    ]);
    if (!launched) {
      print('❌ 拼多多未安装或无法打开');
    } else {
      print('✅ 拼多多搜索已通过 Deep Link 启动: $keyword');
    }
  }

  // 打开拼多多主页（不带搜索词）
  static Future<void> _openPinduoduoHome(Map<String, dynamic> params) async {
    print('🛒 PINDUODU 触发，打开拼多多主页');
    await _launchAnyApp(['pinduoduo://']);
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