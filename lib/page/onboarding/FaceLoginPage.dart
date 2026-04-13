import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/api_client.dart';
import '../../app_fonts.dart';

class FaceLoginPage extends StatefulWidget {
  const FaceLoginPage({super.key});

  @override
  State<FaceLoginPage> createState() => _FaceLoginPageState();
}

class _FaceLoginPageState extends State<FaceLoginPage> {
  bool _isProcessing = false;
  String _statusText = "请点击下方按钮开始刷脸";

  // 💡 唤起前置摄像头拍照并上传
  Future<void> _startFaceScan() async {
    final picker = ImagePicker();
    try {
      // 强制使用前置摄像头
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
      );

      if (image == null) return;

      setState(() {
        _isProcessing = true;
        _statusText = "正在识别中，请稍候...";
      });

      // 构造表单数据传给后端
      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(image.path, filename: "face.jpg"),
        "role": "ELDER",
      });

      // 调用后端的刷脸登录接口
      var response = await ApiClient().post('/api/auth/face-login', data: formData);

      String token = response['token'];
      String userId = response['userId'].toString();
      // 1. 提取刷脸成功后返回的专属音色
      String userVoiceId = response['data']['voiceId'] ?? "longhuhu";

      // 2. 同步给全局管理器
      UserProfileManager().syncVoiceIdFromBackend(userVoiceId);

      // 保存登录态
      ApiClient.globalToken = token;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token);
      await prefs.setString('userId', userId);
      await prefs.setString('role', 'ELDER');
      await prefs.setString('voiceId', userVoiceId);

      setState(() {
        _statusText = "识别成功！欢迎回来。";
      });

      // 跳转到长辈主页前设置头像页（或者直接进主页）
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      });

    } catch (e) {
      setState(() {
        _isProcessing = false;
        String errorMsg = e.toString().replaceAll("Exception: ", "");
        _statusText = "识别失败：$errorMsg\n请重试或使用验证码登录";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("人脸识别登录"),
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 扫描框 UI 动画/占位
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _isProcessing ? Colors.blueAccent : Colors.grey.shade300, width: 4),
                color: Colors.blue.withOpacity(0.05),
              ),
              child: _isProcessing
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 6))
                  : const Icon(Icons.face_retouching_natural, size: 100, color: Colors.blueAccent),
            ),
            const SizedBox(height: 40),

            // 状态提示文字 (大字号适配长辈)
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
            ),

            const SizedBox(height: 60),

            // 操作按钮
            if (!_isProcessing)
              SizedBox(
                width: 250,
                height: 65,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt, size: 28),
                  label: const Text("开始刷脸", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
                  ),
                  onPressed: _startFaceScan,
                ),
              ),
          ],
        ),
      ),
    );
  }
}