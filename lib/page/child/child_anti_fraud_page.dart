import 'package:flutter/material.dart';
import 'package:phone_java/app_fonts.dart';

class ChildAntiFraudPage extends StatefulWidget {
  const ChildAntiFraudPage({super.key});

  @override
  State<ChildAntiFraudPage> createState() => _ChildAntiFraudPageState();
}

class _ChildAntiFraudPageState extends State<ChildAntiFraudPage> {
  // 颜色定义 (保持项目全局统一)
  final Color gray800 = const Color(0xFF1F2937);
  final Color gray500 = const Color(0xFF6B7280);
  final Color gray100 = const Color(0xFFF3F4F6);
  final Color blue600 = const Color(0xFF2563EB);
  final Color blue50 = const Color(0xFFEFF6FF);
  final Color red600 = const Color(0xFFDC2626);
  final Color red50 = const Color(0xFFFEF2F2);

  int _activeTab = 0; // 0: 接听预警, 1: 拦截记录

  // 💡 模拟数据：接听预警 (针对已接听的真实风险)
  final List<Map<String, String>> _warningRecords = [
    {
      "elderName": "爷爷",
      "time": "2025-12-04 15:22:00",
      "duration": "1分15秒",
      "number": "138 **** 4451",
      "location": "湖北省武汉市",
      "type": "疑似冒充公检法", // 风险类型区分于拦截类型
      "status": "已接听"
    },
    {
      "elderName": "爷爷",
      "time": "2025-12-03 09:15:22",
      "duration": "45秒",
      "number": "155 **** 0092",
      "location": "上海市",
      "type": "金融理财诈骗",
      "status": "已接听"
    },
    {
      "elderName": "爷爷",
      "time": "2025-12-01 18:30:10",
      "duration": "2分10秒",
      "number": "177 **** 8823",
      "location": "广东省广州市",
      "type": "虚假中奖诱导",
      "status": "已接听"
    },
  ];

  // 💡 模拟数据：拦截记录 (样式与长辈端完全一致)
  final List<Map<String, String>> _interceptRecords = [
    {"number": "170 9822 4512", "time": "今天 10:42", "location": "重庆市", "type": "标记号码拦截"},
    {"number": "00 852 6451 2231", "time": "昨天 15:20", "location": "中国香港", "type": "境外来电拦截"},
    {"number": "188 2234 5567", "time": "03-23 18:30", "location": "未知归属地", "type": "非通讯录拦截"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const SizedBox(height: 20),
          _buildTopToggle(), // 顶部切换组件
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _activeTab == 0 ? _buildWarningList() : _buildInterceptList(),
            ),
          ),
        ],
      ),
    );
  }

  // 构建顶部切换滑块
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
          _toggleBtn("接听预警", 0),
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
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? blue600 : gray500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 画面一：接听预警
  Widget _buildWarningList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _warningRecords.length,
      itemBuilder: (context, index) {
        final item = _warningRecords[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: red600.withOpacity(0.2)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: red50, shape: BoxShape.circle),
                    child: Icon(Icons.warning_amber_rounded, color: red600, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("高风险通话预警", style: TextStyle(color: red600, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(item['time']!, style: TextStyle(color: gray500, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: gray100, borderRadius: BorderRadius.circular(6)),
                    child: Text(item['status']!, style: TextStyle(color: gray800, fontSize: 11, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              Text(
                "您的长辈【${item['elderName']}】已接听疑似诈骗电话",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: gray800),
              ),
              const SizedBox(height: 12),
              _buildWarningInfoRow("通话时长：", item['duration']!),
              _buildWarningInfoRow("来电号码：", "${item['number']}  (${item['location']})"),
              _buildWarningInfoRow("风险类型：", item['type']!, valueColor: red600),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(color: gray100, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  "提示：该通话已被系统语义识别为高危风险。请立即通过电话或视频联系长辈，确认其是否进行了转账等危险操作。",
                  style: TextStyle(fontSize: 13, color: gray500, height: 1.4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWarningInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: gray500, fontSize: 14)),
          Text(value, style: TextStyle(color: valueColor ?? gray800, fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // 画面二：拦截记录 (完全参考长辈端样式)
  Widget _buildInterceptList() {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _interceptRecords.length,
      separatorBuilder: (context, index) => Divider(color: gray100, height: 32),
      itemBuilder: (context, index) {
        final record = _interceptRecords[index];
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
}