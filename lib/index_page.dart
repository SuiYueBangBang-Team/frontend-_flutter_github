import 'package:phone_java/page/family_page.dart';
import 'package:phone_java/page/health_page.dart';
import 'package:phone_java/page/home_content.dart';
import 'package:phone_java/app_fonts.dart'; //  必须引入含有 FontManager 和 UserProfileManager 的文件
import 'package:phone_java/page/settings_page.dart';
import 'package:phone_java/page/elder_anti_fraud_page.dart';
import 'package:flutter/material.dart';
// 定位相关的插件
import 'package:flutter_bmflocation/flutter_bmflocation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_java/utils/api_client.dart';
import 'dart:async'; //  用于定时器
import 'package:battery_plus/battery_plus.dart'; //  用于获取真实电量
import 'package:volume_controller/volume_controller.dart'; //  用于获取真实系统音量

class IndexPage extends StatefulWidget {
  const IndexPage({super.key});

  @override
  State<IndexPage> createState() => _IndexPageState();
}

class _IndexPageState extends State<IndexPage> {
  int _currentIndex = 0;

  // 颜色定义
  final Color gray800 = const Color(0xFF1F2937);
  final Color gray500 = const Color(0xFF6B7280);
  final Color gray100 = const Color(0xFFF3F4F6);
  final Color blue600 = const Color(0xFF2563EB);
  final Color blue50 = const Color(0xFFEFF6FF);

  late final List<Map<String, dynamic>> _tabs;
  final GlobalKey<FamilyPageState> _familyPageKey = GlobalKey<FamilyPageState>();

  // 长辈端专属的静默后台定位插件
  final LocationFlutterPlugin _locationPlugin = LocationFlutterPlugin();
  // 心跳定时器与硬件状态实例
  Timer? _heartbeatTimer;
  final Battery _battery = Battery();

  @override
  void initState() {
    super.initState();
    _tabs = [
      {
        'title': '帮帮',
        'subtitle': '您的智能助手',
        'icon': Icons.home_outlined,
        'activeIcon': Icons.home_rounded,
        'label': '主页',
        'page': const HomeContent(),
      },
      {
        'title': '健康管家',
        'subtitle': '让帮帮助您管理健康',
        'icon': Icons.favorite_border_rounded,
        'activeIcon': Icons.favorite_rounded,
        'label': '健康',
        'page': const HealthPage(),
      },
      {
        'title': '家人互联',
        'subtitle': '一键联系家人',
        'icon': Icons.people_outline_rounded,
        'activeIcon': Icons.people_rounded,
        'label': '家人',
        'page': FamilyPage(key: _familyPageKey),
      },
      {
        'title': '反诈守护',
        'subtitle': '实时拦截骚扰',
        'icon': Icons.phone_callback_outlined,
        'activeIcon': Icons.phone_callback_rounded,
        'label': '反诈',
        'page': const ElderAntiFraudPage(),
      },
      {
        'title': '设置',
        'subtitle': '一次设置，永久省心',
        'icon': Icons.settings_outlined,
        'activeIcon': Icons.settings_rounded,
        'label': '设置',
        'page': const SettingsPage(),
      },
    ];
    // 长辈一进入主界面，立刻申请权限并开启 5 秒循环定位上报
    _requestPermissionAndStartReport();
    // 新增：立刻启动设备心跳后台轮询
    _startHeartbeatReport();
  }

  @override
  void dispose() {
    //  退出登录或销毁页面时，必须停止定位节省电量
    _locationPlugin.stopLocation();
    // 退出登录或销毁页面时，停止心跳发送
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  // 优化的权限申请逻辑，两步走解决直接跳到设置请求始终位置的问题
  Future<void> _requestPermissionAndStartReport() async {
    await Permission.sms.request();
    // 1. 先像子女端一样，请求普通前台定位权限（会弹出系统默认的授权框）
    PermissionStatus status = await Permission.location.request();

    if (status.isGranted) {
      // 只要拿到了前台权限，就立刻把定位轮询跑起来，保证应用在亮屏时正常工作
      _startElderlyLocationReport();

      // 2. 检查是否已经有了后台定位权限 (locationAlways)
      PermissionStatus alwaysStatus = await Permission.locationAlways.status;

      // 如果还没有后台定位权限，弹出一个我们自定义的温馨提示框，引导长辈去设置
      if (!alwaysStatus.isGranted && mounted) {
        _showBackgroundLocationGuide();
      }
    } else {
      // debugPrint("⚠️ [长辈端] 定位权限被拒绝，无法向子女上报位置！");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("请允许定位权限，否则子女无法确认您的安全")));
      }
    }
  }

  // 引导去设置页开启后台定位的友好弹窗
  void _showBackgroundLocationGuide() {
    showDialog(
      context: context,
      barrierDismissible: false, // 防止误触关掉
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: Colors.blueAccent, size: 28),
            SizedBox(width: 8),
            Text("开启后台守护", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "为了让子女在您手机息屏时也能确认您的安全，请在接下来的设置页面中，将定位权限修改为【始终允许】。",
          style: TextStyle(fontSize: 16, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("稍后再说", style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              //  长辈知情并同意后，再触发强制跳转设置页的逻辑，体验就非常自然了
              await Permission.locationAlways.request();
            },
            child: const Text("去设置", style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
    );
  }


  //  核心：5 秒/次 位置持续上报逻辑
  void _startElderlyLocationReport() async {
    try {
      // debugPrint("📌 [长辈端] 定位流程 1: 设置隐私政策...");
      _locationPlugin.setAgreePrivacy(true);

      // debugPrint("📌 [长辈端] 定位流程 2: 初始化定位参数...");
      BaiduLocationAndroidOption androidOption = BaiduLocationAndroidOption(
        locationMode: BMFLocationMode.hightAccuracy,
        isNeedAddress: false, //  不解析地址（省流省电），只要经纬度
        openGps: true,
        coordType: BMFLocationCoordType.bd09ll,
        scanspan: 7000,
      );
      await _locationPlugin.prepareLoc(androidOption.getMap(), {});

      // debugPrint("📌 [长辈端] 定位流程 3: 注册连续回调...");
      _locationPlugin.seriesLocationCallback(callback: (BaiduLocation result) async {
        if (result.latitude != null && result.longitude != null && result.latitude! > 1.0) {
          // debugPrint("📍 [长辈端] 捕获坐标: 经度=${result.longitude}, 纬度=${result.latitude}，准备上报后端...");

          try {
            // 获取当前时间的 Unix 时间戳（秒）
            int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            await ApiClient().post(
                '/api/location/report?lat=${result.latitude}&lng=${result.longitude}&timestamp=$timestamp'
            );
            // debugPrint("✅ [长辈端] 坐标上报后端成功！");
          } catch (e) {
            // debugPrint("❌ [长辈端] 上报后端失败: $e");
          }

        } else {
          // debugPrint("⚠️ [长辈端] 捕获坐标无效，错误码=${result.errorCode}");
        }
      });

      // debugPrint("📌 [长辈端] 定位流程 4: 正式启动后台定位轮询！");
      await _locationPlugin.startLocation();

    } catch (e) {
      // debugPrint("❌ [长辈端] 定位模块启动异常: $e");
    }
  }

  // 💡 核心新增：长辈端设备心跳后台轮询 (电量、音量、在线状态)
  void _startHeartbeatReport() {
    // 1. 初始化时立刻主动上报一次
    _reportHeartbeat();

    // 2. 开启定时器，每 30 秒上报一次心跳 (后端 Redis 会维持 10 分钟在线，30秒非常安全且省电)
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _reportHeartbeat();
    });
  }

  // 💡 执行具体的心跳拉取与上报
  Future<void> _reportHeartbeat() async {
    try {
      // 1. 获取真实系统电量 (0-100)
      int batteryLevel = await _battery.batteryLevel;

      // 2. 获取真实系统音量 (插件返回 0.0 - 1.0，我们乘以100转为整形)
      double volume = await VolumeController().getVolume();
      int volumeLevel = (volume * 100).toInt();

      // 3. 发送给后端
      // 备注：后端接口要求传 deviceId，但底层实际使用的是 token 里的 userId，所以这里传 Elder_Device 占位即可
      var res = await ApiClient().post(
          '/api/device/htbtreport?deviceId=Elder_Device&battery=$batteryLevel&volume_level=$volumeLevel'
      );

      debugPrint("💓 [长辈端] 设备心跳上报成功！当前电量: $batteryLevel%, 当前音量: $volumeLevel% (30秒后下一次)");
    } catch (e) {
      debugPrint("❌ [长辈端] 设备心跳上报失败: $e");
    }
  }



  @override
  Widget build(BuildContext context) {
    final currentTab = _tabs[_currentIndex];

    //  关键：同时监听字体缩放和用户信息（头像）的变化
    return ListenableBuilder(
      listenable: Listenable.merge([FontManager(), UserProfileManager()]),
      builder: (context, child) {
        return Scaffold(
          extendBody: true,
          backgroundColor: Colors.white,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(100.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: gray100, width: 1)),
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    //  左侧：固定宽度 90，确保不挤压标题
                    SizedBox(
                      width: 90,
                      child: _currentIndex == 0
                          ? Center(
                        child: CircleAvatar(
                          radius: 28, // 放大后的背景圈
                          backgroundColor: blue50,
                          child: Icon(
                            //  从全局管理器获取当前选中的图标
                            UserProfileManager().currentAvatarIcon,
                            color: Colors.blueAccent,
                            size: 38, // 放大后的图标大小
                          ),
                        ),
                      )
                          : null,
                    ),

                    // 中间：标题区域
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 💡 这里同样使用了 FittedBox 确保标题不溢出
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              currentTab['title'],
                              style: TextStyle(
                                  fontSize: AppFonts.titleLarge,
                                  fontWeight: FontWeight.bold,
                                  color: gray800
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              currentTab['subtitle'],
                              style: TextStyle(
                                  fontSize: AppFonts.bodySmall,
                                  color: gray500
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    //  右侧：固定宽度 90 的透明占位，实现标题绝对居中
                    const SizedBox(width: 90),
                  ],
                ),
              ),
            ),
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
          bottomNavigationBar: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 30), // 略微缩小边距以容纳5个按钮
            height: 90,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(44),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 25,
                    offset: const Offset(0, 10)
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly, // 改为 SpaceEvenly 让5个分布更均匀
              children: List.generate(_tabs.length, (index) {
                return _buildNavItem(index, _tabs[index]);
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem(int index, Map<String, dynamic> tab) {
    bool isActive = _currentIndex == index;
    return Flexible( // 💡 使用 Flexible 包裹，确保每个项在等分空间内
      child: GestureDetector(
        onTap: () {
          setState(() => _currentIndex = index);
          // 如果切换到了“家人互联”Tab，静默刷新数据，保证拉到最新的绑定记录
          if (index == 2) {
            _familyPageKey.currentState?.fetchMembers(isSilent: true);
          }
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), // 减少内边距
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
                  size: 28, // 略微减小图标大小(30->28)，为文字腾出空间
                  color: isActive ? blue600 : gray500
              ),
              const SizedBox(height: 2),
              // 💡 关键：底部文字增加 FittedBox，防止“反诈”或“设置”在特大字体下撑破导航栏
              FittedBox(
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