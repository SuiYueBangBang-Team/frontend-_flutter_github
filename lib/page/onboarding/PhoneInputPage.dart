import 'package:flutter/material.dart';
import 'dart:async';
import 'package:phone_java/utils/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PhoneInputPage extends StatefulWidget {
  const PhoneInputPage({super.key});

  @override
  State<PhoneInputPage> createState() => _PhoneInputPageState();
}

class _PhoneInputPageState extends State<PhoneInputPage> {
  // ==========================================
  // 🛠 调试配置区：已将其改为 false，恢复真实后端请求
  // ==========================================
  static const bool _isDebugMode = false;
  // ==========================================

  final TextEditingController controller = TextEditingController();
  bool agree = false;
  bool isSmsSent = false;
  int countdown = 60;
  Timer? timer;
  String currentPhone = "";

  final phoneReg = RegExp(r'^1[3-9]\d{9}$');

  void startCountdown() {
    setState(() {
      isSmsSent = true;
      countdown = 60;
    });
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (countdown > 0) {
        setState(() => countdown--);
      } else {
        t.cancel();
        setState(() => countdown = 0);
      }
    });
  }

  /// 核心逻辑控制
  Future<void> handleButton() async {
    String input = controller.text.trim();

    // 获取当前角色
    final String role = ModalRoute.of(context)?.settings.arguments as String? ?? 'ELDER';

    if (!agree && !_isDebugMode) {
      _showSnackBar("请先勾选用户协议");
      return;
    }

    if (!isSmsSent) {
      // --- 第一阶段：获取验证码 ---
      if (input.isEmpty) {
        _showSnackBar("请输入手机号");
        return;
      }
      if (!phoneReg.hasMatch(input) && !_isDebugMode) {
        _showSnackBar("手机号格式不正确");
        return;
      }

      if (_isDebugMode) {
        debugPrint("🛠 [Debug] 跳过验证码发送接口");
        setState(() {
          currentPhone = input.isEmpty ? "13800008888" : input;
          controller.clear();
        });
        startCountdown();
        _showSnackBar("验证码已发送 (调试模式)");
        return;
      }

      // 💡 恢复：真实发送验证码接口
      try {
        await ApiClient().post('/api/auth/send-sms', data: {"phone": input});
        setState(() {
          currentPhone = input;
          controller.clear();
        });
        startCountdown();
        _showSnackBar("验证码已发送");
      } catch (e) {
        _showSnackBar("发送失败: ${e.toString()}");
      }

    } else {
      // --- 第二阶段：登录验证 ---
      if (input.isEmpty && !_isDebugMode) {
        _showSnackBar("请输入验证码");
        return;
      }

      if (_isDebugMode) {
        debugPrint("🛠 [Debug] 跳过登录验证接口，正在模拟保存本地数据...");
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', "debug_token_12345");
        await prefs.setString('userPhone', currentPhone);
        await prefs.setString('role', role); // 保存角色

        if (mounted) {
          if (role == 'CHILD') {
            Navigator.pushNamedAndRemoveUntil(context, '/child_index', (route) => false);
          } else {
            Navigator.pushNamed(context, '/avatar');
          }
        }
        return;
      }

      // 💡 恢复：真实的登录验证接口，并结合了新版的 role 身份控制
      try {
        _showSnackBar("正在登录...");
        var response = await ApiClient().post('/api/auth/login', data: {
          "phone": currentPhone,
          "code": input,
          "role": role // 传给后端真实的角色
        });
        String token = response['token'];
        String userId = response['userId'].toString();

        ApiClient.globalToken = token;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        await prefs.setString('userId', userId);
        await prefs.setString('userPhone', currentPhone);
        await prefs.setString('role', role);

        _showSnackBar("验证成功！");

        // 根据角色分发跳转路由
        if (mounted) {
          if (role == 'CHILD') {
            Navigator.pushNamedAndRemoveUntil(context, '/child_index', (route) => false);
          } else {
            Navigator.pushNamed(context, '/avatar');
          }
        }
      } catch (e) {
        _showSnackBar("登录失败: ${e.toString()}");
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isButtonActive = _isDebugMode || agree;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                isSmsSent ? "输入验证码" : "手机号登录",
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
              ),
            ),

            const SizedBox(height: 40),

            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              maxLength: isSmsSent ? 6 : 11,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                counterText: "",
                hintText: isSmsSent ? "请输入短信验证码" : "请输入手机号",
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5)),
              ),
            ),

            if (isSmsSent)
              Padding(
                padding: const EdgeInsets.only(top: 12, right: 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: countdown == 0 ? startCountdown : () => _showHelpDialog(),
                    child: Text(
                      countdown == 0 ? "重新获取验证码" : "未收到？($countdown s)",
                      style: TextStyle(color: countdown == 0 ? Colors.blue : Colors.grey[600], fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isButtonActive ? Colors.blueAccent : Colors.grey[300],
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: isButtonActive ? handleButton : null,
                child: Text(
                  !isSmsSent ? "获取验证码" : "立即登录",
                  style: TextStyle(color: isButtonActive ? Colors.white : Colors.grey[500], fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 25),

            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Transform.scale(
                  scale: 1.2,
                  child: Checkbox(
                      value: agree,
                      activeColor: Colors.blueAccent,
                      shape: const CircleBorder(),
                      onChanged: (v) => setState(() => agree = v!)
                  ),
                ),
                const Text("我已阅读并同意", style: TextStyle(fontSize: 14, color: Colors.grey)),
                _protocolText("《用户协议》"),
                const Text("与", style: TextStyle(fontSize: 14, color: Colors.grey)),
                _protocolText("《隐私政策》"),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _protocolText(String text) {
    return GestureDetector(
      onTap: () => _showProtocol(text),
      child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.blueAccent, fontWeight: FontWeight.w500)),
    );
  }

  void _showProtocol(String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: const Text("协议内容加载中..."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("确定"),
          )
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("提示"),
        content: const Text("开发阶段：请输入任意 6 位数字即可通过。"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("知道了"),
          )
        ],
      ),
    );
  }
}