import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';
import '../app_fonts.dart';
import '../utils/api_client.dart';

/// 子女端的紧急救助全屏弹窗
class EmergencyAlertDialog extends StatefulWidget {
  final Map<String, dynamic>? elderInfo;
  final int countdownSeconds;
  final String phoneNumber;
  const EmergencyAlertDialog({
    super.key,
    this.elderInfo,
    this.countdownSeconds = 10,
    this.phoneNumber = '120',
  });

  @override
  State<EmergencyAlertDialog> createState() => _EmergencyAlertDialogState();
}

class _EmergencyAlertDialogState extends State<EmergencyAlertDialog>
    with SingleTickerProviderStateMixin {
  late int _remainingSeconds;
  Timer? _timer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.countdownSeconds;
    _startCountdown();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startVibration();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        t.cancel();
        _onCountdownComplete();
      }
    });
  }

  Future<void> _onCountdownComplete() async {
    await _makePhoneCall();
  }

  Future<void> _makePhoneCall() async {
    final uri = Uri.parse('tel:${widget.phoneNumber}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("无法拨打电话，请检查手机权限")),
        );
      }
    }
  }

  Future<void> _manualCall() async {
    _timer?.cancel();
    await _makePhoneCall();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _dismiss() async {
    _timer?.cancel();
    _stopVibration();
    try {
      await ApiClient().post('/api/emergency/handle', data: {
        "recordId": widget.elderInfo?['recordId'] ?? widget.elderInfo?['id'],
      });
    } catch (e) {}
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _startVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 500, 200, 500], repeat: 0);
    }
  }

  Future<void> _stopVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _stopVibration();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 强制全屏：隐藏状态栏、导航栏，不留任何边距
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFE53935),
      systemNavigationBarColor: Color(0xFFE53935),
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    String elderName = widget.elderInfo?['name'] ?? '您的长辈';
    String location = widget.elderInfo?['location'] ?? "正在获取真实位置...";

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFE53935),
        // 关键：全屏铺满，无任何留白
        body: Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFFE53935),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: SizedBox(
              width: double.infinity,
              height: MediaQuery.of(context).size.height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 脉冲图标
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_rounded,
                        size: 45,
                        color: Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 标题
                  const Text(
                    "紧急救助请求",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),
                  // 信息卡片
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "$elderName 正在请求紧急救助",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.location_on, color: Colors.white70, size: 18),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                location,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  // 倒计时卡片
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "$_remainingSeconds 秒后自动拨打",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 15),
                        LinearProgressIndicator(
                          value: _remainingSeconds / widget.countdownSeconds,
                          minHeight: 10,
                          backgroundColor: Colors.white24,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  // 立即拨打按钮
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    width: double.infinity,
                    height: 70,
                    child: ElevatedButton.icon(
                      onPressed: _manualCall,
                      icon: const Icon(Icons.call, size: 28),
                      label: Text(
                        "立即拨打 ${widget.phoneNumber}",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  // 确认安全按钮
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    width: double.infinity,
                    height: 70,
                    child: ElevatedButton(
                      onPressed: _dismiss,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      child: const Text(
                        "我已确认，长辈安全",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}