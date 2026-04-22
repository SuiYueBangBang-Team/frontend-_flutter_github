import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:phone_java/app_fonts.dart';
import 'package:phone_java/utils/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

class ElderAntiFraudPage extends StatefulWidget {
  const ElderAntiFraudPage({super.key});

  @override
  State<ElderAntiFraudPage> createState() => _ElderAntiFraudPageState();
}

class _ElderAntiFraudPageState extends State<ElderAntiFraudPage> with WidgetsBindingObserver {
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
  bool _isRoleHeld = false;           // CallScreeningService 方案
  bool _hasPhoneStatePerm = false;    // 降级方案（PhoneState）
  bool _hasContactPermission = false;
  bool _isServiceRunning = false;     // 前台拦截服务

  static const _antiFraudChannel = MethodChannel('com.yourcompany.phone_java/anti_fraud');

  bool get _callInterceptReady => _isRoleHeld || _hasPhoneStatePerm || _isServiceRunning;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _antiFraudChannel.setMethodCallHandler(_handleNativeCallback);
    _loadSettings();
    _checkPermissions();
    _loadRecords();
  }

  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    if (call.method == 'roleResult') {
      final bool granted = call.arguments == true;
      debugPrint("收到角色授权结果: $granted");
      await _checkPermissions();
      if (_isRoleHeld) {
        if (!_hasContactPermission) {
          await _requestContactPermission();
        }
      } else {
        // CallScreeningRole 失败，自动尝试降级方案
        await _requestFallbackPermissions();
      }
    } else if (call.method == 'phoneStatePermResult') {
      final bool granted = call.arguments == true;
      debugPrint("收到降级权限结果: $granted");
      await _checkPermissions();
      if (_hasPhoneStatePerm && !_hasContactPermission) {
        await _requestContactPermission();
      }
    }
  }

  Future<void> _requestFallbackPermissions() async {
    try {
      final result = await _antiFraudChannel.invokeMethod('requestPhoneStatePermissions');
      if (result == 'ALREADY_GRANTED') {
        setState(() => _hasPhoneStatePerm = true);
        if (!_hasContactPermission) {
          await _requestContactPermission();
        }
      }
      // 'REQUESTING' 的结果会通过 phoneStatePermResult 回调处理
    } catch (e) {
      debugPrint("请求降级权限失败: $e");
    }
  }

  Future<void> _requestContactPermission() async {
    final status = await Permission.contacts.request();
    setState(() => _hasContactPermission = status.isGranted);
  }

  Future<void> _startAntiFraudService() async {
    try {
      await _antiFraudChannel.invokeMethod('startAntiFraudService');
      setState(() => _isServiceRunning = true);
    } catch (e) {
      debugPrint("启动反诈前台服务失败: $e");
    }
  }

  Future<void> _stopAntiFraudService() async {
    try {
      await _antiFraudChannel.invokeMethod('stopAntiFraudService');
      setState(() => _isServiceRunning = false);
    } catch (e) {
      debugPrint("停止反诈前台服务失败: $e");
    }
  }

  Future<void> _syncServiceState() async {
    bool anyEnabled = _markIntercept || _contactOnly || _overseasIntercept;
    if (anyEnabled) {
      await _startAntiFraudService();
    } else {
      await _stopAntiFraudService();
    }
  }

  Future<void> _loadRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final userId = prefs.getString('userId') ?? '';

      // 从服务器拉取
      List<Map<String, String>> serverRecords = [];
      if (userId.isNotEmpty) {
        try {
          final response = await ApiClient().get('/api/fraud/reports', queryParameters: {'userId': userId});
          if (response != null && response is List) {
            for (var item in response) {
              final modelResult = (item['modelResult'] ?? '').toString();
              if (item['recordType'] == 'INTERCEPT' || modelResult.contains('拦截')) {
                serverRecords.add({
                  'number': item['phoneNumber'] ?? '',
                  'type': (item['modelResult'] ?? '').toString().replaceAll(' [系统拦截]', ''),
                  'time': item['createTime'] ?? '',
                  'location': item['location'] ?? '',
                  'synced': 'true',
                });
              }
            }
          }
        } catch (e) {
          debugPrint("从服务器拉取拦截记录失败: $e");
        }
      }

      // 本地记录
      final jsonStr = prefs.getString('blockedCallRecords') ?? '[]';
      final List<dynamic> localList = jsonDecode(jsonStr);
      final localRecords = localList.map((e) {
        final m = e as Map;
        return m.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      }).toList();

      // 合并：服务器优先，本地未同步的补充进去
      final serverNumbers = serverRecords.map((r) => r['number']).toSet();
      final unsynced = localRecords.where((r) => r['synced'] != 'true' && !serverNumbers.contains(r['number'])).toList();

      setState(() {
        _records = [...serverRecords, ...unsynced];
      });

      if (unsynced.isNotEmpty) {
        _syncRecordsToServer();
      }
    } catch (e) {
      debugPrint("加载拦截记录失败: $e");
    }
  }

  bool _isSyncing = false;

  Future<void> _syncRecordsToServer() async {
    if (_isSyncing) return;
    _isSyncing = true;
    debugPrint("🔄 [反诈同步] 开始扫描未同步记录...");

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('blockedCallRecords') ?? '[]';
      List<dynamic> list = jsonDecode(jsonStr);
      
      int syncCount = 0;
      bool hasChange = false;

      for (var i = 0; i < list.length; i++) {
        var record = list[i];
        // 如果 native 存入时没带 synced，或者明确为 false，则需要补发
        if (record['synced'] == true) continue;

        try {
          debugPrint("📤 [反诈同步] 正在补发: ${record['number']} (${record['time']})");
          await ApiClient().post('/api/fraud/report-intercept', data: {
            'phoneNumber': record['number'],
            'blockType': record['type'],
            'time': record['time'],
            'location': record['location'] ?? ''
          });
          
          list[i]['synced'] = true;
          syncCount++;
          hasChange = true;
        } catch (e) {
          debugPrint("❌ [反诈同步] 单条同步失败: $e");
          // 如果出现 401 说明登录失效，停止本次同步
          if (e.toString().contains("401")) break;
        }
      }

      if (hasChange) {
        await prefs.setString('blockedCallRecords', jsonEncode(list));
        debugPrint("✅ [反诈同步] 巡检完成，成功补发 $syncCount 条记录");
      } else {
        debugPrint("ℹ️ [反诈同步] 无需同步的内容");
      }
    } catch (e) {
      debugPrint("⚠️ [反诈同步] 巡检流程异常: $e");
    } finally {
      _isSyncing = false;
    }
  }

  List<Map<String, String>> _records = [];

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
        onTap: () {
          setState(() => _activeTab = index);
          if (index == 1) _loadRecords();
        },
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      _loadRecords();
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final bool roleHeld = await _antiFraudChannel.invokeMethod('checkCallScreeningRole');
      final bool phoneStatePerm = await _antiFraudChannel.invokeMethod('checkPhoneStatePermissions');
      final bool serviceRunning = await _antiFraudChannel.invokeMethod('isAntiFraudServiceRunning');
      final bool contactOk = await Permission.contacts.isGranted;
      setState(() {
        _isRoleHeld = roleHeld;
        _hasPhoneStatePerm = phoneStatePerm;
        _isServiceRunning = serviceRunning;
        _hasContactPermission = contactOk;
      });
    } catch (e) {
      debugPrint("检查权限状态失败: $e");
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _markIntercept = prefs.getBool('markIntercept') ?? false;
      _contactOnly = prefs.getBool('contactOnly') ?? false;
      _overseasIntercept = prefs.getBool('overseasIntercept') ?? false;
    });
    // 如果有开关已开启，自动启动前台拦截服务
    if (_markIntercept || _contactOnly || _overseasIntercept) {
      _startAntiFraudService();
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    await _syncServiceState();
  }

  Widget _buildFunctionList() {
    return ListView(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 120),
      children: [
        _buildStatusCard(),
        const SizedBox(height: 20),
        _buildSwitchTile(
          title: "标记号码拦截",
          subtitle: "拒接标记为骚扰、诈骗的号码",
          value: _markIntercept,
          onChanged: (v) {
            setState(() => _markIntercept = v);
            _saveSetting('markIntercept', v);
          },
          icon: Icons.shield_outlined,
        ),
        _buildSwitchTile(
          title: "非通讯录拦截",
          subtitle: "拒接所有不在通讯录中的陌生号码",
          value: _contactOnly,
          onChanged: (v) async {
            if (v) {
              // 开启时处理权限逻辑
              var status = await Permission.contacts.request();
              if (!status.isGranted) return;
            }
            setState(() => _contactOnly = v);
            _saveSetting('contactOnly', v);
          },
          icon: Icons.person_add_disabled_outlined,
        ),
        _buildSwitchTile(
          title: "境外来电拦截",
          subtitle: "拒接来自海外及港澳台地区的电话",
          value: _overseasIntercept,
          onChanged: (v) {
            setState(() => _overseasIntercept = v);
            _saveSetting('overseasIntercept', v);
          },
          icon: Icons.public_off_outlined,
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            "说明：点击「一键开启权限」即可启用来电拦截功能。开启上方开关后，系统将按规则自动挂断可疑电话。",
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
    bool isPrimary = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPrimary ? blue600.withOpacity(0.1) : blue50.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPrimary ? blue600.withOpacity(0.3) : blue50),
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
    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 64, color: gray100),
            const SizedBox(height: 16),
            Text("暂无拦截记录", style: TextStyle(fontSize: 18, color: gray500)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 120),
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
                      Text(record['phoneNumber'] ?? record['number'] ?? '未知号码', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                            record['blockType'] ?? record['type'] ?? '未知类型',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(record['time'] ?? '', style: TextStyle(color: gray500, fontSize: 15)),
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
      await ApiClient().post('/api/fraud/settings', data: {'type': type, 'enabled': status});
    } catch (e) {
      debugPrint("更新失败: $e");
    }
  }

  // 状态诊断卡片
  Widget _buildStatusCard() {
    bool allOk = _callInterceptReady && _hasContactPermission;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: allOk ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: allOk ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(allOk ? Icons.check_circle : Icons.warning_amber_rounded,
                   color: allOk ? Colors.green : Colors.orange, size: 24),
              const SizedBox(width: 10),
              Text(
                allOk ? "系统拦截服务已就绪" : "拦截服务待配置",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: allOk ? Colors.green[700] : Colors.orange[700]
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _statusRow("来电拦截权限", _callInterceptReady),
          const SizedBox(height: 8),
          _statusRow("前台拦截服务", _isServiceRunning),
          const SizedBox(height: 8),
          _statusRow("通讯录访问", _hasContactPermission),
          if (!allOk) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _onFixPermissions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: blue600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text("一键开启权限"),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _onFixPermissions() async {
    if (!_callInterceptReady) {
      // 先尝试 CallScreeningRole（系统级静默拦截）
      final roleResult = await _antiFraudChannel.invokeMethod('requestCallScreeningRole');
      if (roleResult == 'ALREADY_HELD') {
        setState(() => _isRoleHeld = true);
      } else if (roleResult == 'REQUESTING') {
        return; // 等待 roleResult 回调
      } else {
        // CallScreeningRole 不可用，直接走降级方案
        await _requestFallbackPermissions();
        return;
      }
    }
    if (!_hasContactPermission) {
      await _requestContactPermission();
    }
  }

  Widget _statusRow(String label, bool ok) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        const Spacer(),
        Text(ok ? "正常" : "未开启", 
             style: TextStyle(color: ok ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
