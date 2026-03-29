import 'dart:async';
import 'package:flutter/material.dart';
import '../app_fonts.dart';       // 💡 使用相对路径
import '../utils/api_client.dart'; // 💡 引入请求客户端

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

  @override
  void initState() {
    super.initState();
    // 💡 页面加载时自动获取家人作为紧急联系人
    _fetchEmergencyContacts();
    startTimer();

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
        "location": "北京市朝阳区建国路88号"
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已自动发短信给紧急联系人")));
    } catch (e) {}
  }

  Future<void> _handleImmediateCall() async {
    try {
      await ApiClient().post('/api/emergency/trigger', data: {
        "type": "MANUAL",
        "location": "北京市朝阳区建国路88号"
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("正在拨打120并通知家属...")));
    } catch (e) {}
  }

  @override
  void dispose() {
    timer?.cancel();
    _iconController.dispose();
    super.dispose();
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
                  _buildInfoCard(icon: Icons.location_on, title: "实时位置已定位", subtitle: "北京市朝阳区建国路88号"),
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