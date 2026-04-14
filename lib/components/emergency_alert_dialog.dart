import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';
import '../app_fonts.dart';
import '../utils/api_client.dart';

/// 子女端的紧急救助全屏弹窗
/// 长辈触发紧急求助后，子女端会弹出此窗口
/// 倒计时结束后自动拨打指定号码
class EmergencyAlertDialog extends StatefulWidget {
  /// 紧急求助的长辈信息（可选）
  final Map<String, dynamic>? elderInfo;
  /// 倒计时秒数（默认10秒）
  final int countdownSeconds;
  /// 倒计时结束要拨打的电话号码
  final String phoneNumber;

  const EmergencyAlertDialog({
    super.key,
    this.elderInfo,
    this.countdownSeconds = 10,
    this.phoneNumber = '13106961519',
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

    // 脉冲动画
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 弹窗显示时开始震动
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

    // 调用后端接口标记紧急救助已处理
    try {
      await ApiClient().post('/api/emergency/handle', data: {
        "recordId": widget.elderInfo?['recordId'] ?? widget.elderInfo?['id'],
      });
    } catch (e) {
      // 处理失败不影响关闭弹窗
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  // 开始震动（紧急模式：持续震动）
  Future<void> _startVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      // Android: 震动模式 [等待0ms, 震动500ms, 等待200ms, 震动500ms] 循环
      if (await Vibration.hasAmplitudeControl() ?? false) {
        Vibration.vibrate(pattern: [0, 500, 200, 500], repeat: 0);
      } else {
        // 不支持振幅控制，使用简单持续震动
        Vibration.vibrate(duration: 500);
      }
    }
  }

  // 停止震动
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
    String elderName = widget.elderInfo?['name'] ?? '您家长辈';

    return PopScope(
      canPop: false, // 禁止侧滑返回
      child: Scaffold(
        backgroundColor: const Color(0xFFB71C1C),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              children: [
                const Spacer(flex: 1),

                // 脉冲警告图标
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_rounded,
                      size: 70,
                      color: Color(0xFFB71C1C),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // 主标题
                Text(
                  "紧急救助请求",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppFonts.titleLarge + 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 20),

                // 副标题
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "$elderName 正在请求紧急救助",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: AppFonts.titleLarge,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // 显示长辈位置
                      if (widget.elderInfo?['location'] != null &&
                          widget.elderInfo?['location'] != '未知位置' &&
                          widget.elderInfo?['location'] != '正在获取真实位置...')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_on, color: Colors.white70, size: 18),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  widget.elderInfo?['location'] ?? '',
                                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        "请尽快确认长辈安全状况",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: AppFonts.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 1),

                // 倒计时区域
                Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "$_remainingSeconds 秒后自动拨打",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: AppFonts.titleLarge,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: _remainingSeconds / widget.countdownSeconds,
                          minHeight: 12,
                          backgroundColor: Colors.white24,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 手动拨号按钮
                SizedBox(
                  width: double.infinity,
                  height: 70,
                  child: ElevatedButton.icon(
                    onPressed: _manualCall,
                    icon: const Icon(Icons.call, size: 28),
                    label: Text(
                      "立即拨打 ${widget.phoneNumber}",
                      style: TextStyle(
                        fontSize: AppFonts.bodyLarge,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFB71C1C),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                // 忽略按钮
                SizedBox(
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
                    child: Text(
                      "我已确认，长辈安全",
                      style: TextStyle(
                        fontSize: AppFonts.bodyLarge,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
