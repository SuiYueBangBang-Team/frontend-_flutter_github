import 'package:flutter/material.dart';
import 'package:phone_java/app_fonts.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:phone_java/utils/api_client.dart';
import 'package:phone_java/utils/voice_intent_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart'; // 💡 新增：音频播放插件

class HomeContent extends StatefulWidget {
  const HomeContent({super.key});

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _isProcessing = false;
  late AnimationController _waveController;
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _recorder = AudioRecorder();

  // 💡 新增：音频播放器实例
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 💡 注意：这里必须和你的 ApiClient 中的 baseUrl 保持一致！
  // 如果你在 ApiClient 中用的是 10.0.2.2，这里也要换成 10.0.2.2
  final String _baseUrl = "http://10.0.2.2:9000";

  final List<Map<String, String>> _messages = [
    {"role": "ai", "content": "您好！我是帮帮，有什么可以帮您？"},
  ];

  final StreamController<String> _aiStreamController = StreamController<String>.broadcast();

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 💡 修改：增加 audioUrl 参数
  void _startAiStreamResponse(String fullResponse, {String audioUrl = ""}) async {
    // 💡 如果后端返回了音频链接，直接开始播放
    if (audioUrl.isNotEmpty) {
      try {
        String fullAudioUrl = "$_baseUrl$audioUrl";
        await _audioPlayer.play(UrlSource(fullAudioUrl));
      } catch (e) {
        debugPrint("音频播放失败: $e");
      }
    }

    String currentDisplay = "";
    setState(() => _messages.add({"role": "ai", "content": ""}));

    for (int i = 0; i < fullResponse.length; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
      currentDisplay += fullResponse[i];
      _aiStreamController.add(currentDisplay);
      _messages.last["content"] = currentDisplay;
      _scrollToBottom();
    }
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _startAiStreamResponse("没有录音权限，请在系统设置中开启麦克风权限。");
      return;
    }

    final directory = await getTemporaryDirectory();
    final filePath = '${directory.path}/record.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        bitRate: 128000,
        sampleRate: 8000,
      ),
      path: filePath,
    );

    setState(() => _isRecording = true);
    _waveController.repeat();
  }

  Future<void> _stopRecordingAndUpload() async {
    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });
    _waveController.stop();

    final path = await _recorder.stop();
    if (path == null || path.isEmpty) {
      setState(() => _isProcessing = false);
      _startAiStreamResponse("录音失败，请重试。");
      return;
    }

    try {
      final formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(path, filename: "record.wav"),
      });
      final response = await ApiClient().post('/api/chat/parse-audio', data: formData); // 💡 注意这里最好和后端接口名对齐

      final recognizedText = response['recognizedText'] ?? "";
      final voiceFeedback = response['voiceFeedback'] ?? response['reply'] ?? response['message'] ?? "";
      final audioUrl = response['audioUrl'] ?? ""; // 💡 提取音频链接
      final action = response['action']?.toString();
      final params = response['params'] is Map ? Map<String, dynamic>.from(response['params']) : <String, dynamic>{};

      if (recognizedText.toString().isNotEmpty) {
        setState(() {
          _messages.add({"role": "user", "content": recognizedText.toString()});
        });
      }

      // 💡 传入 audioUrl
      _startAiStreamResponse(voiceFeedback.toString().isNotEmpty ? voiceFeedback.toString() : "已收到语音指令", audioUrl: audioUrl);
      await VoiceIntentHandler.handle(action: action, params: params);
    } catch (e) {
      _startAiStreamResponse("语音识别失败，请稍后再试。($e)");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // 💡 真实请求：发送语音/文本问 AI
  Future<void> _sendToAi(String text) async {
    setState(() {
      _messages.add({"role": "user", "content": text});
    });
    _scrollToBottom();

    try {
      var response = await ApiClient().post('/api/chat/send', data: {
        "content": text,
        "type": "TEXT"
      });

      String reply = response['reply'] ?? "帮帮听不懂，能再说一遍吗？";
      String audioUrl = response['audioUrl'] ?? ""; // 💡 提取后端返回的音频链接

      // 💡 传入 audioUrl 触发播放
      _startAiStreamResponse(reply, audioUrl: audioUrl);
    } catch (e) {
      _startAiStreamResponse("网络好像出错了，请稍后再试。($e)");
    }
  }

  Future<void> _handleCameraAction() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image == null) {
      return;
    }

    setState(() => _messages.add({"role": "user", "content": "[发送了一张图片]"}));
    _scrollToBottom();

    try {
      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(image.path, filename: "upload.jpg"),
      });
      var response = await ApiClient().post('/api/chat/upload-image', data: formData);
      _startAiStreamResponse(response['reply'] ?? "帮帮没有识别出内容，请再试一次。");
    } catch (e) {
      _startAiStreamResponse("图片上传失败了，请稍后再试。($e)");
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _scrollController.dispose();
    _aiStreamController.close();
    _recorder.dispose();
    _audioPlayer.dispose(); // 💡 释放播放器资源
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double sideBoxWidth = 100.0;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  bool isAi = msg['role'] == 'ai';

                  if (isAi && index == _messages.length - 1 && _isRecording == false) {
                    return StreamBuilder<String>(
                      stream: _aiStreamController.stream,
                      initialData: msg['content'],
                      builder: (context, snapshot) => _buildChatBubble(snapshot.data ?? "", isAi),
                    );
                  }
                  return _buildChatBubble(msg['content']!, isAi);
                },
              ),
              if (_isRecording)
                Positioned(
                  top: 20, left: 0, right: 0,
                  child: SizedBox(height: 100, child: CustomPaint(painter: SiriWavePainter(_waveController))),
                ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.only(bottom: 150, left: 20, right: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: sideBoxWidth),
              const Spacer(),
              GestureDetector(
                onTapDown: (_) {
                  if (_isProcessing) return;
                  _startRecording();
                },
                onTapUp: (_) {
                  if (_isProcessing) return;
                  _stopRecordingAndUpload();
                },
                child: _buildMicButton(),
              ),
              const Spacer(),
              SizedBox(
                width: sideBoxWidth,
                child: GestureDetector(
                  onTap: _handleCameraAction,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle,
                          border: Border.all(color: Colors.blueAccent, width: 2),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.blueAccent, size: 28),
                      ),
                      const SizedBox(height: 6),
                      const Text("拍照问", style: TextStyle(fontSize: AppFonts.bodySmall, color: Colors.blueAccent, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatBubble(String text, bool isAi) {
    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.only(bottom: 20, left: isAi ? 0 : 40, right: isAi ? 40 : 0),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: isAi ? Colors.white : const Color(0xFFE0F2FE),
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomLeft: isAi ? const Radius.circular(0) : const Radius.circular(20),
            bottomRight: isAi ? const Radius.circular(20) : const Radius.circular(0),
          ),
          boxShadow: isAi ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)] : null,
        ),
        child: Text(text, style: const TextStyle(fontSize: AppFonts.titleMedium, height: 1.4, color: Colors.black87)),
      ),
    );
  }

  Widget _buildMicButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 130, height: 130,
      decoration: BoxDecoration(
        color: _isRecording ? Colors.redAccent : Colors.blueAccent,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: (_isRecording ? Colors.red : Colors.blue).withOpacity(0.4), blurRadius: 20)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mic, color: Colors.white, size: 42),
          const SizedBox(height: 8),
          Text(_isRecording ? "松开发送" : "按着说话", style: const TextStyle(color: Colors.white, fontSize: AppFonts.bodyMedium, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class SiriWavePainter extends CustomPainter {
  final Animation<double> animation;
  SiriWavePainter(this.animation) : super(repaint: animation);
  @override
  void paint(Canvas canvas, Size size) {
    final double time = animation.value * 2 * math.pi;
    _drawWave(canvas, size, time, color: Colors.lightBlueAccent.withOpacity(0.4), amplitude: 25, frequency: 2, phaseShift: 0);
    _drawWave(canvas, size, time, color: Colors.cyanAccent.withOpacity(0.3), amplitude: 15, frequency: 3, phaseShift: math.pi/2);
  }
  void _drawWave(Canvas canvas, Size size, double time, {required Color color, required double amplitude, required double frequency, required double phaseShift}) {
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 3.5..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);
    final path = Path();
    for (double x = 0; x <= size.width; x++) {
      double normX = x / size.width;
      double y = size.height / 2 + math.sin(normX * math.pi * frequency + time + phaseShift) * amplitude * math.sin(normX * math.pi);
      if (x == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(SiriWavePainter oldDelegate) => true;
}