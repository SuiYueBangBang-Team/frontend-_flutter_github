import 'package:flutter/material.dart';
import 'package:phone_java/app_fonts.dart';
import 'package:phone_java/utils/api_client.dart';

class ElderAntiFraudPage extends StatefulWidget {
  const ElderAntiFraudPage({super.key});

  @override
  State<ElderAntiFraudPage> createState() => _ElderAntiFraudPageState();
}

class _ElderAntiFraudPageState extends State<ElderAntiFraudPage> {
  // 颜色定义
  final Color gray800 = const Color(0xFF1F2937);
  final Color gray500 = const Color(0xFF6B7280);
  final Color gray100 = const Color(0xFFF3F4F6);
  final Color blue600 = const Color(0xFF2563EB);
  final Color blue50 = const Color(0xFFEFF6FF);

  // 状态变量：默认全部关闭
  int _activeTab = 0; // 0: 功能选择, 1: 拦截记录
  bool _markIntercept = false;
  bool _contactOnly = false;
  bool _overseasIntercept = false;

  // 💡 模拟记录：Type 已修改为与功能开关名称完全对应
  final List<Map<String, String>> _records = [
    {"number": "170 9822 4512", "time": "今天 10:42", "location": "重庆市", "type": "标记号码拦截"},
    {"number": "00 852 6451 2231", "time": "昨天 15:20", "location": "中国香港", "type": "境外来电拦截"},
    {"number": "131 4567 8901", "time": "03-24 09:15", "location": "广东省广州市", "type": "标记号码拦截"},
    {"number": "188 2234 5567", "time": "03-23 18:30", "location": "未知归属地", "type": "非通讯录拦截"},
    {"number": "00 1 212 555 0199", "time": "03-22 11:05", "location": "美国", "type": "境外来电拦截"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const SizedBox(height: 20),
          _buildTopToggle(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _activeTab == 0 ? _buildFunctionList() : _buildRecordList(),
            ),
          ),
        ],
      ),
    );
  }

  // 顶部切换滑块
  Widget _buildTopToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: gray100,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          _toggleBtn("功能选择", 0),
          _toggleBtn("拦截记录", 1),
        ],
      ),
    );
  }

  Widget _toggleBtn(String title, int index) {
    bool isSelected = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
                : [],
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? blue600 : gray500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 画面一：功能选择
  Widget _buildFunctionList() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSwitchTile(
          title: "标记号码拦截",
          subtitle: "拒接标记为骚扰、诈骗的号码",
          value: _markIntercept,
          onChanged: (v) => setState(() => _markIntercept = v),
          icon: Icons.shield_outlined,
        ),
        _buildSwitchTile(
          title: "非通讯录拦截",
          subtitle: "拒接所有不在通讯录中的陌生号码",
          value: _contactOnly,
          onChanged: (v) => setState(() => _contactOnly = v),
          icon: Icons.person_add_disabled_outlined,
        ),
        _buildSwitchTile(
          title: "境外来电拦截",
          subtitle: "拒接来自海外及港澳台地区的电话",
          value: _overseasIntercept,
          onChanged: (v) => setState(() => _overseasIntercept = v),
          icon: Icons.public_off_outlined,
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            "说明：开启上方开关后，系统将自动挂断对应类型的来电，保护您的财产安全。",
            style: TextStyle(color: Colors.grey, height: 1.5, fontSize: 14),
          ),
        )
      ],
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: blue50.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: blue50),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(icon, color: blue600),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 14, color: gray500)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeColor: blue600,
            onChanged: (v) {
              onChanged(v);
              _updateInterceptionSetting(title, v);
            },
          ),
        ],
      ),
    );
  }

  // 拦截记录
  Widget _buildRecordList() {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _records.length,
      separatorBuilder: (context, index) => Divider(color: gray100, height: 32),
      itemBuilder: (context, index) {
        final record = _records[index];
        return Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.phone_disabled_rounded, color: Colors.redAccent, size: 26),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(record['number']!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.redAccent.withOpacity(0.2))
                          ),
                          child: Text(
                            record['type']!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text("${record['location']} | ${record['time']}", style: TextStyle(color: gray500, fontSize: 15)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _updateInterceptionSetting(String type, bool status) async {
    try {
      // 后端同步逻辑
    } catch (e) {
      debugPrint("更新失败: $e");
    }
  }
}