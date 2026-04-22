// AI辅助生成：Antigravity，2026-04-21
// 功能：子女端反诈模块 - 短信预警(含确认训练闭环) + 拦截记录

import 'package:flutter/material.dart';
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

class ChildAntiFraudPageState extends State<ChildAntiFraudPage> with SingleTickerProviderStateMixin {
  // ── 颜色系统 ──────────────────────────────────────────
  static const Color _gray800 = Color(0xFF1F2937);
  static const Color _gray500 = Color(0xFF6B7280);
  static const Color _gray100 = Color(0xFFF3F4F6);
  static const Color _blue600 = Color(0xFF2563EB);
  static const Color _blue50  = Color(0xFFEFF6FF);
  static const Color _red600  = Color(0xFFDC2626);
  static const Color _red50   = Color(0xFFFEF2F2);
  static const Color _green600 = Color(0xFF16A34A);
  static const Color _amber600 = Color(0xFFD97706);

  // ── 状态 ─────────────────────────────────────────────
  int _activeTab = 0; // 0: 短信预警, 1: 拦截记录
  bool _isLoading = true;
  List<Map<String, dynamic>> _warningRecords = [];
  List<Map<String, String>>  _interceptRecords = [];

  late final AnimationController _fabAnim;

  @override
  void initState() {
    super.initState();
    _fabAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    fetchData();
  }

  @override
  void dispose() {
    _fabAnim.dispose();
    super.dispose();
  }

  // ── 数据拉取 ─────────────────────────────────────────
  Future<void> fetchData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId') ?? '';
      debugPrint('🚀 [反诈] 拉取记录, userId=$userId');

      final response = await ApiClient().get(
        '/api/fraud/reports',
        queryParameters: {'userId': userId},
      );

      if (response != null && response is List) {
        final List<Map<String, dynamic>> warnings  = [];
        final List<Map<String, String>>  intercepts = [];

        for (final item in response) {
          final String timeStr = item['createTime'] != null
              ? DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(item['createTime']))
              : '未知时间';

          final int userConfirm = (item['userConfirm'] ?? -1) as int;
          final String statusLabel = userConfirm == 1
              ? '已确认诈骗'
              : userConfirm == 0
                  ? '误报/安全'
                  : '待核实';

          if (item['recordType'] == 'INTERCEPT') {
            intercepts.add({
              'elderName': (item['elderName'] ?? '长辈').toString(),
              'time'     : timeStr,
              'number'   : (item['phoneNumber'] ?? '未知号码').toString(),
              'location' : (item['location'] ?? '').toString(),
              'type'     : (item['modelResult'] ?? '系统拦截')
                  .toString()
                  .replaceAll(' [系统拦截]', ''),
            });
          } else {
            // ── 短信预警记录 ──
            // 💡 过滤掉已经处理过的预警，让列表充当“待办收件箱”
            if (userConfirm == -1) {
              warnings.add({
                'reportId': (item['id'] ?? 0).toString(),
                'elderName': (item['elderName'] ?? '长辈').toString(),
                'time': timeStr,
                'content': (item['content'] ?? '').toString(),
                'fraudType': (item['modelResult'] ?? '疑似诈骗').toString(),
                'status': statusLabel,
                'userConfirm': userConfirm,
              });
            }
          }
        }

        setState(() {
          _warningRecords  = warnings;
          _interceptRecords = intercepts;
        });
      }
    } catch (e) {
      debugPrint('❌ [反诈] 加载失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('同步反诈数据失败，请检查网络')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── 子女确认诈骗/误报 ──────────────────────────────────
  Future<void> _confirmSms(String reportId, int confirm, int index) async {
    // 乐观更新 UI
    setState(() {
      _warningRecords[index]['userConfirm'] = confirm;
      _warningRecords[index]['status'] = confirm == 1 ? '已确认诈骗' : '误报/安全';
    });

    try {
      final response = await ApiClient().post(
        '/api/fraud/confirm',
        data: {'reportId': int.parse(reportId), 'confirm': confirm},
      );

      if (mounted) {
        final int added = (response is Map ? (response['keywordsAdded'] ?? 0) : 0) as int;
        final String msg = confirm == 1
            ? added > 0
                ? '✅ 已确认！系统提取了 $added 个关键词加入训练库'
                : '✅ 已确认为诈骗信息'
            : '已标记为误报/安全';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: confirm == 1 ? _green600 : _gray500,
            duration: const Duration(seconds: 3),
          ),
        );

        // 💡 延迟 800ms，让用户看完动画和提示后，将卡片从列表中移除
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            setState(() {
              _warningRecords.removeWhere((element) => element['reportId'] == reportId);
            });
          }
        });
      }
    } catch (e) {
      // 回滚乐观更新
      setState(() {
        _warningRecords[index]['userConfirm'] = -1;
        _warningRecords[index]['status'] = '待核实';
      });
      debugPrint('❌ [反诈确认] 失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请重试'), backgroundColor: _red600),
        );
      }
    }
  }

  // ── 批量操作 ─────────────────────────────────────────
  Future<void> _confirmAll(int confirm) async {
    // 显示加载圈
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: _blue600)),
    );

    int successCount = 0;
    int addedKeywords = 0;
    final List<Map<String, dynamic>> itemsToProcess = List.from(_warningRecords);

    for (var item in itemsToProcess) {
      try {
        final response = await ApiClient().post(
          '/api/fraud/confirm',
          data: {'reportId': int.parse(item['reportId'] as String), 'confirm': confirm},
        );
        successCount++;
        if (confirm == 1 && response is Map) {
          addedKeywords += (response['keywordsAdded'] ?? 0) as int;
        }
      } catch (e) {
        debugPrint('❌ [批量确认] 失败: $e');
      }
    }

    // 关闭加载圈
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    if (mounted) {
      setState(() {
        _warningRecords.clear(); // 批量处理完后清空当前视图
      });

      final String msg = confirm == 1
          ? '✅ 已批量确认 $successCount 条，提取 $addedKeywords 个关键词'
          : '✅ 已将 $successCount 条批量标为安全';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: confirm == 1 ? _green600 : _gray500,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildBatchActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: () => _confirmAll(0),
            icon: const Icon(Icons.check_circle_outline, size: 14),
            label: const Text('全标安全', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _gray500,
              side: const BorderSide(color: Color(0xFFE5E7EB)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              minimumSize: const Size(0, 32),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _confirmAll(1),
            icon: const Icon(Icons.warning_amber_rounded, size: 14),
            label: const Text('全认诈骗', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _red600,
              side: BorderSide(color: _red600.withOpacity(0.3)),
              backgroundColor: _red50,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              minimumSize: const Size(0, 32),
            ),
          ),
        ],
      ),
    );
  }

  // ── 构建 ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const SizedBox(height: 20),
          _buildTopToggle(),
          // 新增：只有在预警 tab 且有数据时，显示批量操作按钮
          if (_activeTab == 0 && _warningRecords.isNotEmpty) 
            _buildBatchActions(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: fetchData,
              color: _blue600,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _blue600))
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: _activeTab == 0
                          ? (_warningRecords.isEmpty   ? _buildEmptyState(0) : _buildWarningList())
                          : (_interceptRecords.isEmpty ? _buildEmptyState(1) : _buildInterceptList()),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 顶部切换 ─────────────────────────────────────────
  Widget _buildTopToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _gray100, borderRadius: BorderRadius.circular(30)),
      child: Row(
        children: [
          _toggleBtn('短信预警', 0),
          _toggleBtn('电话拦截', 1),
        ],
      ),
    );
  }

  Widget _toggleBtn(String title, int index) {
    final bool sel = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            boxShadow: sel
                ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))]
                : [],
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                color: sel ? _blue600 : _gray500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 页面一：短信预警列表 ──────────────────────────────
  Widget _buildWarningList() {
    return ListView.builder(
      key: const ValueKey('warning'),
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 120),
      itemCount: _warningRecords.length,
      itemBuilder: (context, index) => _buildWarningCard(_warningRecords[index], index),
    );
  }

  Widget _buildWarningCard(Map<String, dynamic> item, int index) {
    final int confirmVal = (item['userConfirm'] ?? -1) as int;
    final bool isPending = confirmVal == -1;
    final bool isConfirmed = confirmVal == 1;

    // badge 样式
    Color badgeColor;
    Color badgeBg;
    if (isPending) {
      badgeColor = _amber600;
      badgeBg    = const Color(0xFFFEF3C7);
    } else if (isConfirmed) {
      badgeColor = _red600;
      badgeBg    = _red50;
    } else {
      badgeColor = _green600;
      badgeBg    = const Color(0xFFDCFCE7);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPending ? _red600.withOpacity(0.25) : Colors.grey.withOpacity(0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: isPending ? _red600.withOpacity(0.06) : Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 卡片头部 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isPending ? _red50 : _gray100.withOpacity(0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isPending ? _red600.withOpacity(0.12) : Colors.grey.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.sms_failed_rounded,
                    color: isPending ? _red600 : _gray500,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '疑似诈骗短信预警',
                        style: TextStyle(
                          color: isPending ? _red600 : _gray500,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        item['time'] as String,
                        style: const TextStyle(color: _gray500, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // 状态 badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item['status'] as String,
                    style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // ── 卡片主体 ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行
                Row(
                  children: [
                    const Icon(Icons.elderly, color: _blue600, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '您的长辈【${item['elderName']}】收到一条疑似诈骗短信',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _gray800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 短信内容展示框
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isPending ? _red50 : _gray100.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isPending ? _red600.withOpacity(0.15) : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    item['content'] as String? ?? '（无内容）',
                    style: const TextStyle(fontSize: 14, color: _gray800, height: 1.5),
                  ),
                ),
                const SizedBox(height: 10),

                // AI识别类型
                _infoRow(
                  icon: Icons.local_police_outlined,
                  label: 'AI识别类型：',
                  value: item['fraudType'] as String,
                  valueColor: _red600,
                ),

                // 操作按钮（仅待核实状态显示）
                if (isPending) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      // 误报/安全
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmSms(item['reportId'] as String, 0, index),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _gray500,
                            side: const BorderSide(color: Color(0xFFD1D5DB)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('误报/安全', style: TextStyle(fontSize: 14)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 确认诈骗
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _confirmSms(item['reportId'] as String, 1, index),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _red600,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          icon: const Icon(Icons.warning_amber_rounded, size: 18),
                          label: const Text('确认诈骗', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],

                // 已确认提示
                if (isConfirmed) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.model_training, color: _red600, size: 16),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '关键词已提交训练库，模型将自动更新以保护更多老人',
                            style: TextStyle(fontSize: 12, color: _red600, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({required IconData icon, required String label, required String value, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: _gray500),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: _gray500, fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? _gray800,
                fontSize: 13,
                fontWeight: valueColor != null ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 页面二：拦截记录 ──────────────────────────────────
  Widget _buildInterceptList() {
    return ListView.separated(
      key: const ValueKey('intercept'),
      padding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 120),
      itemCount: _interceptRecords.length,
      separatorBuilder: (_, __) => Divider(color: _gray100, height: 28),
      itemBuilder: (context, index) {
        final record = _interceptRecords[index];
        return Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.phone_disabled_rounded, color: Colors.redAccent, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          record['number']!,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _gray800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                        ),
                        child: Text(
                          record['type']!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '保护长辈：${record['elderName']}',
                    style: const TextStyle(color: _blue600, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    record['time']!,
                    style: const TextStyle(color: _gray500, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── 空状态 ────────────────────────────────────────────
  Widget _buildEmptyState(int tab) {
    return Center(
      key: ValueKey('empty_$tab'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            tab == 0 ? Icons.mark_email_read_outlined : Icons.phone_missed_outlined,
            size: 80,
            color: _gray100,
          ),
          const SizedBox(height: 16),
          Text(
            tab == 0 ? '暂无短信预警' : '暂无拦截记录',
            style: const TextStyle(color: _gray500, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            '帮帮正在默默守护您的长辈 💙',
            style: TextStyle(color: _gray500.withOpacity(0.6), fontSize: 14),
          ),
        ],
      ),
    );
  }
}