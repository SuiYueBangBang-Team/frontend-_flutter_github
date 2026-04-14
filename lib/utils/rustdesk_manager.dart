import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phone_java/utils/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// 远程协助管理器（新架构：引导安装第三方插件 + 后台唤醒信令）
///
/// 核心思路：
///   - 老人端：通过三步向导引导安装第三方远控插件（如 ToDesk）
///   - 子女端：点击远控后拉取凭证，弹窗唤醒长辈端，长辈端心跳扫到后弹窗并自动唤起插件
class RustDeskManager {
  static final RustDeskManager _instance = RustDeskManager._internal();
  factory RustDeskManager() => _instance;
  RustDeskManager._internal();

  /// 第三方辅助插件包名（ToDesk 原生端）
  static const String _remoteAppPackage = 'youqu.android.todesk';
  static const String _remoteAppName = 'ToDesk';

  /// MethodChannel（用于调起第三方 App）
  static const MethodChannel _channel = MethodChannel('com.yourcompany.phone_java/rustdesk');

  // ============================================================
  //  长辈端相关方法
  // ============================================================

  /// App 启动时初始化：检测插件是否安装，若已安装则静默唤起到后台保活
  Future<void> initHostService() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool remoteEnabled = prefs.getBool('remote_control_enabled') ?? false;
      if (!remoteEnabled) {
        print('ℹ️ [远程协助] 长辈未开启远控开关，跳过初始化');
        return;
      }

      bool installed = await isRemoteAppInstalled();
      if (installed) {
        print('✅ [远程协助] 检测到辅助插件已安装，静默唤起后台服务...');
        await _launchRemoteAppBackground();
      }

      // 同步上次保存的凭证到后端
      String? savedId = prefs.getString('remote_app_id');
      String? savedPass = prefs.getString('remote_app_password');
      if (savedId != null && savedId.isNotEmpty) {
        await uploadCredentialsToServer(savedId, savedPass ?? '');
      }
    } catch (e) {
      print('❌ [远程协助] 初始化失败: $e');
    }
  }

  /// 检测辅助插件是否已安装
  Future<bool> isRemoteAppInstalled() async {
    try {
      final result = await _channel.invokeMethod('isPackageInstalled', {'packageName': _remoteAppPackage});
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// 后台静默唤起第三方远控插件（让它驻留在后台保持 ID 活跃）
  Future<void> _launchRemoteAppBackground() async {
    try {
      await _channel.invokeMethod('launchPackage', {'packageName': _remoteAppPackage});
    } catch (e) {
      print('⚠️ [远程协助] 后台唤起失败，插件可能需要用户手动打开一次: $e');
    }
  }

  /// 唤起第三方远控插件到前台（用户有交互行为时调用，不会被系统拦截）
  Future<void> launchRemoteAppForeground() async {
    try {
      final Uri appUri = Uri.parse('todesk://');
      bool launched = await launchUrl(appUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await _channel.invokeMethod('launchPackage', {'packageName': _remoteAppPackage});
      }
    } catch (e) {
      // 兜底：跳到应用商店下载
      final Uri storeUri = Uri.parse('market://details?id=$_remoteAppPackage');
      try {
        await launchUrl(storeUri, mode: LaunchMode.externalApplication);
      } catch (_) {
        final Uri browserUri = Uri.parse(
            'https://www.todesk.com/download.html');
        await launchUrl(browserUri, mode: LaunchMode.externalApplication);
      }
    }
  }

  /// 保存凭证到本地并上报后端
  Future<bool> saveAndReportCredentials(String id, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('remote_app_id', id.trim());
      await prefs.setString('remote_app_password', password.trim());
      await uploadCredentialsToServer(id.trim(), password.trim());
      print('✅ [远程协助] 凭证已保存并上报: $id');
      return true;
    } catch (e) {
      print('❌ [远程协助] 凭证保存/上报失败: $e');
      return false;
    }
  }

  /// 上报凭证到业务后端
  Future<void> uploadCredentialsToServer(String uuid, String pass) async {
    try {
      await ApiClient().post('/api/device/rustdesk/report', data: {
        'rustdesk_uuid': uuid,
        'rustdesk_password': pass,
      });
      print('✅ [远程协助] 成功同步 ID 和密码到系统后端');
    } catch (e) {
      print('❌ [远程协助] 上报请求失败: $e');
    }
  }

  /// 清空远程凭证（关闭开关时调用）
  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remote_app_id');
    await prefs.remove('remote_app_password');
    // 后端同步清空
    try {
      await ApiClient().post('/api/device/rustdesk/report', data: {
        'rustdesk_uuid': '',
        'rustdesk_password': '',
      });
    } catch (_) {}
    print('🗑️ [远程协助] 凭证已清空');
  }

  // ============================================================
  //  子女端相关方法
  // ============================================================

  /// 拉取老人的凭证（同时触发后端向长辈写入唤醒指令）
  Future<Map<String, String>?> fetchElderRemoteInfo(int elderId) async {
    try {
      final data = await ApiClient().get(
        '/api/children/getRemoteControlInfo',
        queryParameters: {'elderId': elderId},
      );
      if (data != null && data is Map) {
        return {
          'uuid': data['rustdesk_uuid']?.toString() ?? '',
          'password': data['rustdesk_password']?.toString() ?? '',
        };
      }
      return null;
    } catch (e) {
      print('❌ [远程协助] 拉取凭证请求失败: $e');
      return null;
    }
  }

  /// 子女端发起远控：拉取凭证 → 打开 ToDesk → 提示输入 ID
  Future<void> connectToRemoteElder(BuildContext context, String targetUuid, String targetPassword) async {
    // 尝试唤起子女自己手机上的 ToDesk
    final uri = Uri.parse('todesk://');
    try {
      bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('URI Scheme 无响应');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('请您在自己的手机上打开 $_remoteAppName，输入长辈的设备码: $targetUuid，密码: $targetPassword'),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  // ============================================================
  //  UI 组件：三步向导对话框
  // ============================================================

  /// 展示三步配置向导（长辈端设置页调用）
  static Future<bool?> showSetupWizard(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _RemoteSetupWizardDialog(),
    );
  }

  /// 展示 ID 修改对话框
  static Future<bool?> showIdInputDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => _IdInputDialog(),
    );
  }
}

// ============================================================
//  三步向导对话框
// ============================================================
class _RemoteSetupWizardDialog extends StatefulWidget {
  const _RemoteSetupWizardDialog();

  @override
  State<_RemoteSetupWizardDialog> createState() => _RemoteSetupWizardDialogState();
}

class _RemoteSetupWizardDialogState extends State<_RemoteSetupWizardDialog> {
  int _step = 0; // 当前步骤 0/1/2
  bool _isChecking = false;

  final List<Map<String, dynamic>> _steps = [
    {
      'icon': Icons.store_rounded,
      'iconColor': Colors.teal,
      'title': '第 1 步：安装辅助插件',
      'desc': '我们将为您打开手机应用商店，\n搜索并安装"ToDesk"辅助远控应用。\n\n安装完成后请返回本页面，继续下一步。',
      'btnText': '前往安装',
    },
    {
      'icon': Icons.vpn_key_rounded,
      'iconColor': Colors.orange,
      'title': '第 2 步：查看您的设备代码',
      'desc': '请点击下方按钮打开 ToDesk，\n查看主界面上的"设备代码"和"临时密码"，\n记住或抄写下来，然后返回本页面。',
      'btnText': '打开 ToDesk 查看',
    },
    {
      'icon': Icons.edit_note_rounded,
      'iconColor': Colors.blueAccent,
      'title': '第 3 步：填写凭证',
      'desc': '请将您在 ToDesk 中看到的代码\n和密码填入下方，完成配置。\n\n配置后，子女即可安全地辅助您。',
      'btnText': '填写代码完成配置',
    },
  ];

  Future<void> _handleStepAction() async {
    final manager = RustDeskManager();

    if (_step == 0) {
      // 跳去应用商店
      final storeUri = Uri.parse('market://details?id=${RustDeskManager._remoteAppPackage}');
      bool launched = false;
      try {
        launched = await launchUrl(storeUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
      if (!launched) {
        await launchUrl(
          Uri.parse('https://www.todesk.com/download.html'),
          mode: LaunchMode.externalApplication,
        );
      }
      // 等用户装完让他们自己下一步
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('安装完成后请回来，点击"下一步"继续')),
        );
      }
    } else if (_step == 1) {
      // 拉起 ToDesk 让用户看 ID
      await manager.launchRemoteAppForeground();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('记住设备代码和密码后请回到本 App，点击"下一步"')),
        );
      }
    } else {
      // 最后一步：弹出 ID 录入框
      if (!mounted) return;
      Navigator.pop(context); // 先关向导
      bool? saved = await RustDeskManager.showIdInputDialog(context);
      if (mounted && context.mounted) {
        Navigator.pop(context, saved == true);
      }
      return;
    }
  }

  void _checkAndNext() async {
    if (_step == 0) {
      // 检查一下有没有装上
      setState(() => _isChecking = true);
      bool installed = await RustDeskManager().isRemoteAppInstalled();
      setState(() => _isChecking = false);
      if (!installed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('还未检测到辅助插件，请先完成安装再点下一步')),
        );
        return;
      }
    }
    if (mounted) setState(() => _step++);
  }

  @override
  Widget build(BuildContext context) {
    final s = _steps[_step];
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (s['iconColor'] as Color).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(s['icon'] as IconData, color: s['iconColor'] as Color, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(s['title'] as String, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 步骤进度点
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _step == i ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _step >= i ? Colors.teal : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            )),
          ),
          const SizedBox(height: 18),
          Text(s['desc'] as String, style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87)),
          const SizedBox(height: 20),
          // 操作按钮（根据步骤显示"前往"或"填写"）
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _handleStepAction,
              icon: Icon(_step == 0 ? Icons.open_in_new : (_step == 1 ? Icons.launch : Icons.edit), size: 18),
              label: Text(s['btnText'] as String),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: s['iconColor'] as Color),
                foregroundColor: s['iconColor'] as Color,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消', style: TextStyle(color: Colors.grey)),
        ),
        if (_step < 2)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isChecking ? null : _checkAndNext,
            child: _isChecking
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('已完成，下一步 →', style: TextStyle(color: Colors.white)),
          ),
      ],
    );
  }
}

// ============================================================
//  ID 录入对话框
// ============================================================
class _IdInputDialog extends StatefulWidget {
  @override
  State<_IdInputDialog> createState() => _IdInputDialogState();
}

class _IdInputDialogState extends State<_IdInputDialog> {
  final _idController = TextEditingController();
  final _passController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      _idController.text = prefs.getString('remote_app_id') ?? '';
      _passController.text = prefs.getString('remote_app_password') ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.vpn_key_rounded, color: Colors.teal, size: 26),
        SizedBox(width: 10),
        Expanded(child: Text('填写远程连接凭证', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('请将 ToDesk 主界面显示的设备代码和密码填写于下方：',
              style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.5)),
          const SizedBox(height: 16),
          TextField(
            controller: _idController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '智能设备代码',
              hintText: '如: 123 456 789',
              prefixIcon: const Icon(Icons.perm_identity),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passController,
            decoration: InputDecoration(
              labelText: '临时安全密码',
              hintText: '主界面上的数字密码',
              prefixIcon: const Icon(Icons.lock_outline),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _isSaving ? null : () async {
            if (_idController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入远控设备代码')));
              return;
            }
            setState(() => _isSaving = true);
            bool ok = await RustDeskManager().saveAndReportCredentials(
              _idController.text, _passController.text,
            );
            setState(() => _isSaving = false);
            if (context.mounted) {
              Navigator.pop(context, ok);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ok ? '✅ 远程协助已配置成功！' : '❌ 配置失败，请重试')),
              );
            }
          },
          child: _isSaving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('确认保存', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    _passController.dispose();
    super.dispose();
  }
}
