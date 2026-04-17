import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:phone_java/app_fonts.dart';
import 'package:phone_java/components/emergency_alert_dialog.dart';
import 'package:phone_java/main.dart' show navigatorKey;

import 'child_anti_fraud_page.dart';
import 'child_community_page.dart';
import 'child_health_page.dart';
import 'child_location_page.dart';
import 'child_settings_page.dart';
import '../../utils/api_client.dart';

class ChildIndexPage extends StatefulWidget {
  const ChildIndexPage({super.key});

  @override
  State<ChildIndexPage> createState() => _ChildIndexPageState();
}

class _ChildIndexPageState extends State<ChildIndexPage> {
  @override
  void initState() {
    super.initState();
    _startEmergencyPolling();
  }

  @override
  void dispose() {
    _emergencyPollingTimer?.cancel();
    super.dispose();
  }

  void _startEmergencyPolling() {
    _checkEmergency();
    _checkFraudAlert();
    _emergencyPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkEmergency();
      _checkFraudAlert();
    });
  }

  Future<void> _checkFraudAlert() async {
    if (_isFraudDialogShowing) return;
    try {
      var data = await ApiClient().get('/api/fraud/check-alert');
      if (data != null && data['triggered'] == true && mounted) {
        _isFraudDialogShowing = true;
        
        // 🚨 启动高强度持续震动 (模式与紧急救助一致)
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(pattern: [0, 500, 200, 500], repeat: 0);
        }

        await showDialog(
          context: navigatorKey.currentContext ?? context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                SizedBox(width: 10),
                Text('反诈预警', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('您的长辈可能正在面临电信诈骗，请立即联系核实！', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                Text('诈骗类型：${data['fraudType']}', style: const TextStyle(color: Colors.redAccent)),
                const SizedBox(height: 8),
                Text('短信内容：${data['content']}', style: const TextStyle(fontSize: 14, color: Colors.black87)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Vibration.cancel(); // 停止震动
                  Navigator.pop(ctx);
                },
                child: const Text('我知道了', style: TextStyle(fontSize: 14)),
              ),
              ElevatedButton(
                onPressed: () {
                  Vibration.cancel();
                  Navigator.pop(ctx);
                  // 🚀 核心修复：切换到反诈标签页并触发刷新
                  setState(() => _currentIndex = 3);
                  // 延时一下确保页面已由于 IndexStack 激活
                  Future.delayed(const Duration(milliseconds: 100), () {
                    antiFraudKey.currentState?.fetchData();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('查看详情', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        _isFraudDialogShowing = false;
      }
    } catch (e) {
      debugPrint('反诈轮询失败: $e');
    }
  }

  Future<void> _checkEmergency() async {
    if (_isEmergencyDialogShowing) return;

    try {
      var data = await ApiClient().get('/api/emergency/check');
      print("🔍 [紧急救助轮询] 收到响应: $data");

      if (data != null && data['triggered'] == true && mounted) {
        print("🚨 [紧急救助轮询] 检测到紧急救助！准备弹窗...");
        print("   - 长辈信息: ${data['elderInfo']}");

        _isEmergencyDialogShowing = true;
        _emergencyPollingTimer?.cancel();

        showDialog(
          context: navigatorKey.currentContext ?? context,
          barrierDismissible: false,
          builder: (context) => EmergencyAlertDialog(
            elderInfo: data['elderInfo'],
            countdownSeconds: data['countdown'] ?? 10,
            phoneNumber: '120',  // 子女端帮长辈拨打120急救
          ),
        ).then((_) {
          print("✅ [紧急救助轮询] 弹窗已关闭");
          _isEmergencyDialogShowing = false;
          _startEmergencyPolling();
        });
      } else {
        print("✅ [紧急救助轮询] 无紧急救助: triggered=${data?['triggered']}");
      }
    } catch (e) {
      print("❌ [紧急救助轮询] 请求失败: $e");
    }
  }

  int _currentIndex = 0;

  // 紧急救助轮询定时器
  Timer? _emergencyPollingTimer;
  bool _isEmergencyDialogShowing = false;
  bool _isFraudDialogShowing = false;

  final Color gray800 = const Color(0xFF1F2937);
  final Color gray500 = const Color(0xFF6B7280);
  final Color gray100 = const Color(0xFFF3F4F6);
  final Color blue600 = const Color(0xFF2563EB);
  final Color blue50 = const Color(0xFFEFF6FF);

  final List<Map<String, dynamic>> _tabs = [
    {
      'title': '',
      'subtitle': '',
      'icon': Icons.location_on_outlined,
      'activeIcon': Icons.location_on_rounded,
      'label': '定位',
      'page': const ChildLocationPage(),
    },
    {
      'title': '健康督促',
      'subtitle': '随时督促长辈保持身体健康',
      'icon': Icons.favorite_border_rounded,
      'activeIcon': Icons.favorite_rounded,
      'label': '健康',
      'page': const ChildHealthPage(),
    },
    {
      'title': '子女社区',
      'subtitle': '交流守护心得',
      'icon': Icons.forum_outlined,
      'activeIcon': Icons.forum_rounded,
      'label': '社区',
      'page': const ChildCommunityPage(),
    },
    {
      'title': '反诈守护',
      'subtitle': '实时提醒，保护家人财产',
      'icon': Icons.phone_callback_outlined, // 电话图案
      'activeIcon': Icons.phone_callback_rounded,
      'label': '反诈',
      'page': ChildAntiFraudPage(key: antiFraudKey),
    },
    {
      'title': '系统设置',
      'subtitle': '账号隐私与功能管理',
      'icon': Icons.settings_outlined,
      'activeIcon': Icons.settings_rounded,
      'label': '设置',
      'page': const ChildSettingsPage(),
    },
  ];

  @override
  Widget build(BuildContext context) {
    final currentTab = _tabs[_currentIndex];

    return ListenableBuilder(
      listenable: FontManager(),
      builder: (context, child) {
        return Scaffold(
          extendBody: true,
          backgroundColor: Colors.white,
          appBar: _currentIndex == 0
              ? null
              : PreferredSize(
            preferredSize: const Size.fromHeight(100.0),
            child: _buildCustomAppBar(currentTab),
          ),
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [blue50, blue50.withOpacity(0.4), Colors.white],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
            child: IndexedStack(
              index: _currentIndex,
              children: _tabs.map((tab) => tab['page'] as Widget).toList(),
            ),
          ),
          bottomNavigationBar: _buildFloatingNavigationBar(),
        );
      },
    );
  }

  // 💡 自定义 AppBar，加入 FittedBox 防止标题在特大字体时溢出
  Widget _buildCustomAppBar(Map<String, dynamic> tab) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: gray100, width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const SizedBox(width: 80), // 两边留白适当缩小一点，给中间腾位置
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tab['title'] ?? '',
                      style: TextStyle(
                        fontSize: AppFonts.titleLarge,
                        fontWeight: FontWeight.bold,
                        color: gray800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tab['subtitle'] ?? '',
                      style: TextStyle(
                        fontSize: AppFonts.bodySmall,
                        color: gray500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 80),
          ],
        ),
      ),
    );
  }

  // 💡 底部导航栏：调整边距和对齐方式以适配5个按钮
  Widget _buildFloatingNavigationBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 30), // 略微缩小外边距以容纳5个按钮
      height: 90,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(44),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly, // 均分剩余空间
        children: List.generate(_tabs.length, (index) {
          return _buildNavItem(index, _tabs[index]);
        }),
      ),
    );
  }

  // 💡 导航项构建：加入 Flexible 和 FittedBox，调整内外边距
  Widget _buildNavItem(int index, Map<String, dynamic> tab) {
    bool isActive = _currentIndex == index;
    return Flexible( // 确保每个 Item 在等分空间内，不会互相挤压
      child: GestureDetector(
        onTap: () {
          setState(() => _currentIndex = index);
          // 💡 如果切换到的是反诈页，主动触发一次刷新
          if (index == 3) {
            antiFraudKey.currentState?.fetchData();
          }
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), // 减少内边距为5个按钮腾出空间
          decoration: BoxDecoration(
            color: isActive ? blue50 : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isActive ? tab['activeIcon'] : tab['icon'],
                size: 28, // 略微减小图标大小 (从30降到28)
                color: isActive ? blue600 : gray500,
              ),
              const SizedBox(height: 2),
              FittedBox( // 防止特大字体时文字撑爆导航栏
                fit: BoxFit.scaleDown,
                child: Text(
                  tab['label'],
                  style: TextStyle(
                    fontSize: AppFonts.caption,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    color: isActive ? blue600 : gray500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}