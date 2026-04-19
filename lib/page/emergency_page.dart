// AI辅助生成：豆包，2026-03-15
// 功能：紧急求助页面、倒计时、定位上报

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_fonts.dart';       //  使用相对路径
import '../utils/api_client.dart'; //  引入请求客户端
import 'package:flutter_bmflocation/flutter_bmflocation.dart'; //  引入百度定位
import 'package:permission_handler/permission_handler.dart'; //  引入权限申请

class EmergencyPage extends StatefulWidget {
  const EmergencyPage({super.key});

  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> with SingleTickerProviderStateMixin {
  int seconds = 8;
  Timer? timer;
  late AnimationController _iconController;
  late Animation<double> _iconAnimation;

  List<Map<String, dynamic>> contacts = [];

  // 真实位置变量与定位插件
  String currentLocation = "正在获取真实位置...";
  final LocationFlutterPlugin _locationPlugin = LocationFlutterPlugin();

  @override
  void initState() {
    super.initState();
    //  页面加载时自动获取家人作为紧急联系人
    _fetchEmergencyContacts();
    startTimer();

    // 新增：页面加载时立即请求权限并获取真实定位
    _checkPermissionAndLocate();

    _iconController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _iconAnimation = Tween(begin: 1.0, end: 1.15).animate(CurvedAnimation(parent: _iconController, curve: Curves.easeInOut));
  }

  Future<void> _fetchEmergencyContacts() async {
    try {
      var res = await ApiClient().get('/api/emergency/contacts');
      setState(() {
        contacts = List<Map<String, dynamic>>.from(res ?? []);
      });
    } catch (e) {
      print("加载急救联系人失败: $e");
    }
  }

  void startTimer() {
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (seconds > 0) {
        setState(() => seconds--);
      } else {
        t.cancel();
        _onAutoCallTriggered();
      }
    });
  }

  Future<void> _onAutoCallTriggered() async {
    try {
      await ApiClient().post('/api/emergency/trigger', data: {
        "type": "AUTO",
        "location": currentLocation // 💡 替换为真实位置
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已自动发短信给紧急联系人")));
    } catch (e) {}

    // 倒计时结束后自动拨打120
    _makePhoneCall('120');
  }

  // 新增：直接拨打电话的方法
  Future<void> _makePhoneCall(String phoneNumber) async {
    try {
      // 使用 url_launcher 拨打电话
      final uri = Uri.parse('tel:$phoneNumber');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      print("拨打电话失败: $e");
    }
  }

  Future<void> _handleImmediateCall() async {
    try {
      await ApiClient().post('/api/emergency/trigger', data: {
        "type": "MANUAL",
        "location": currentLocation // 💡 替换为真实位置
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("正在拨打120并通知家属...")));
    } catch (e) {}

    // 立即拨打120
    _makePhoneCall('120');
  }

  // AI辅助生成：DeepSeek-R1-0528，2026-03-16
  // 功能：页面资源释放、定时器销毁、停止定位服务
  @override
  void dispose() {
    timer?.cancel();
    _iconController.dispose();
    // 页面销毁时务必停止定位，防止内存泄露
    _locationPlugin.stopLocation();
    super.dispose();
  }

  // 💡 获取定位权限
  Future<void> _checkPermissionAndLocate() async {
    PermissionStatus status = await Permission.location.request();
    if (status.isGranted) {
      _startRealLocation();
    } else {
      setState(() {
        currentLocation = "未授权定位权限，无法获取位置";
      });
    }
  }

  // 💡 启动真实单次定位
  void _startRealLocation() async {
    _locationPlugin.setAgreePrivacy(true);

    BaiduLocationAndroidOption androidOption = BaiduLocationAndroidOption(
      locationMode: BMFLocationMode.hightAccuracy,
      isNeedAddress: true, // 必须开启地址解析，否则全是经纬度数字
      openGps: true,
      coordType: BMFLocationCoordType.bd09ll,
      scanspan: 1000, // 持续轮询，直到百度把中文街道名解析出来
    );
    await _locationPlugin.prepareLoc(androidOption.getMap(), {});

    _locationPlugin.seriesLocationCallback(callback: (BaiduLocation result) {
      if (!mounted) return;

      // 💡 拦截：如果百度只给了经纬度，还没把中文街道解析出来，就跳过等下一秒
      if (result.address == null && result.locationDetail == null) {
        return;
      }

      // 拿到真实地址后，更新 UI
      setState(() {
        currentLocation = result.locationDetail ?? result.address ?? "未知位置";
      });

      // 💡 拿到中文地址后，立刻掐断定位，省电！
      _locationPlugin.stopLocation();
    });

    await _locationPlugin.startLocation();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FontManager(),
      builder: (context, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFE53935),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
              child: Column(
                children: [
                  ScaleTransition(
                    scale: _iconAnimation,
                    child: Container(width: 90, height: 90, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.warning_rounded, size: 50, color: Colors.red)),
                  ),
                  const SizedBox(height: 20),
                  Text("紧急求助已启动", style: TextStyle(color: Colors.white, fontSize: AppFonts.titleLarge, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  // 💡 替换为真实位置变量
                  _buildInfoCard(icon: Icons.location_on, title: "实时位置已定位", subtitle: currentLocation),
                  const SizedBox(height: 20),
                  _buildContactSection(),
                  const SizedBox(height: 20),
                  _buildTimerSection(),
                  const SizedBox(height: 30),
                  _buildEmergencyButton(),
                  const SizedBox(height: 15),
                  _buildCancelButton(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard({required IconData icon, required String title, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(25)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: Colors.white, size: 28), const SizedBox(width: 8), Text(title, style: const TextStyle(color: Colors.white, fontSize: AppFonts.bodyLarge, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: AppFonts.bodySmall)),
      ]),
    );
  }

  Widget _buildContactSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(25)),
      child: Column(
        children: [
          const Text("正在通知联系人", style: TextStyle(color: Colors.white, fontSize: AppFonts.bodyLarge, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          if (contacts.isEmpty) const Text("正在拉取数据库联系人...", style: TextStyle(color: Colors.white70)),
          ...contacts.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(child: Text(c['name'] ?? "", style: const TextStyle(color: Colors.white, fontSize: AppFonts.bodyMedium))),
                Text(c['phone'] ?? "", style: const TextStyle(color: Colors.white60, fontSize: AppFonts.bodySmall)),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }

  Widget _buildTimerSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(25)),
      child: Column(children: [
        Text("$seconds 秒后自动拨打", style: const TextStyle(color: Colors.white, fontSize: AppFonts.bodyLarge, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        LinearProgressIndicator(value: seconds / 8, minHeight: 10, backgroundColor: Colors.white24, color: Colors.white)
      ]),
    );
  }

  Widget _buildEmergencyButton() {
    return SizedBox(
      width: double.infinity, height: 75,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.call, size: 28),
        label: const Text("立即拨打 120", style: TextStyle(fontSize: AppFonts.bodyLarge, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
        onPressed: _handleImmediateCall,
      ),
    );
  }

  Widget _buildCancelButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: double.infinity, height: 75,
        decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(22)),
        child: const Center(child: Text("× 取消，我误触了", style: TextStyle(color: Colors.white, fontSize: AppFonts.bodyLarge, fontWeight: FontWeight.bold))),
      ),
    );
  }
}