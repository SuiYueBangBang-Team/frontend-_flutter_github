// AI辅助生成：豆包，2026-03-18
// 功能：社区定位、反诈列表、接口调用、开关状态

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phone_java/app_fonts.dart';
import 'package:phone_java/utils/api_client.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 💡 增加 GlobalKey 控制，方便首页切换标签时触发刷新
final GlobalKey<ChildAntiFraudPageState> antiFraudKey = GlobalKey<ChildAntiFraudPageState>();

class ChildAntiFraudPage extends StatefulWidget {
  const ChildAntiFraudPage({super.key});

  @override
  State<ChildAntiFraudPage> createState() => ChildAntiFraudPageState();
}

class ChildAntiFraudPageState extends State<ChildAntiFraudPage> {
  // 颜色定义 (保持项目全局统一)
  final Color gray800 = const Color(0xFF1F2937);
  final Color gray500 = const Color(0xFF6B7280);
  final Color gray100 = const Color(0xFFF3F4F6);
  final Color blue600 = const Color(0xFF2563EB);
  final Color blue50 = const Color(0xFFEFF6FF);
  final Color red600 = const Color(0xFFDC2626);
  final Color red50 = const Color(0xFFFEF2F2);

  int _activeTab = 0; // 0: 接听预警, 1: 拦截记录
  bool _isLoading = true;

  // 💡 真实数据存储
  List<Map<String, String>> _warningRecords = [];
  List<Map<String, String>> _interceptRecords = [];

  @override
  void initState() {
    super.initState();
    fetchData(); // 初始加载
  }

  Future<void> fetchData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId') ?? '';
      debugPrint("🚀 [前端调试] 开始请求反诈记录, 从本地获取到的 userId: $userId");
      
      var response = await ApiClient().get('/api/fraud/reports', queryParameters: {'userId': userId});
      debugPrint("✅ [前端调试] 收到反诈记录响应: $response");
      
      if (response != null && response is List) {
        List<Map<String, String>> warnings = [];
        List<Map<String, String>> intercepts = [];

        for (var item in response) {
          // 将后端实体映射为 UI 格式
          Map<String, String> record = {
            "elderName": item['elderName'] ?? "长辈",
            "time": item['createTime'] != null 
                ? DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(item['createTime']))
                : "未知时间",
            "duration": item['duration'] ?? "未知",
            "number": item['phoneNumber'] ?? item['number'] ?? "未知号码",
            "location": item['location'] ?? "未知",
            "type": item['modelResult'] ?? "疑似诈骗",
            "status": item['userConfirm'] == 1 ? "已确认" : (item['userConfirm'] == 0 ? "误报" : "待核实"),
            "content": item['content'] ?? ""
          };

          // 这里的逻辑根据实际业务划分：
          if (item['recordType'] == 'INTERCEPT') {
            intercepts.add(record);
          } else {
            warnings.add(record);
          }
        }

        setState(() {
          _warningRecords = warnings;
          _interceptRecords = intercepts;
        });
      }
    } catch (e) {
      debugPrint("获取反诈数据失败: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("同步反诈数据失败，请检查网络"))
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const SizedBox(height: 20),
          _buildTopToggle(), // 顶部切换组件
          Expanded(
            child: RefreshIndicator(
              onRefresh: fetchData, // 支持下拉刷新
              color: blue600,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _isLoading 
                    ? const Center(child: CircularProgressIndicator())
                    : ( (_activeTab == 0 ? _warningRecords : _interceptRecords).isEmpty 
                        ? _buildEmptyState()
                        : (_activeTab == 0 ? _buildWarningList() : _buildInterceptList())
                      ),
              ),
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
              _buildWarningInfoRow("通话内容：", item['content']!),
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
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: TextStyle(color: valueColor ?? gray800, fontSize: 14, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // 画面二：拦截记录
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
                  Text("受保护长辈：${record['elderName']}", style: TextStyle(color: blue600, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text("${record['location']} | ${record['time']}", style: TextStyle(color: gray500, fontSize: 15)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 80, color: gray100),
          const SizedBox(height: 16),
          Text("暂无反诈记录", style: TextStyle(color: gray500, fontSize: 18)),
          const SizedBox(height: 8),
          Text("帮帮正在默默守护您的长辈", style: TextStyle(color: gray500.withOpacity(0.6), fontSize: 14)),
        ],
      ),
    );
  }
}