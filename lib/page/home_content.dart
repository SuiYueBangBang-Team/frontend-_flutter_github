import 'package:flutter/material.dart';
import 'package:phone_java/app_fonts.dart';
import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:phone_java/utils/api_client.dart';
import 'package:phone_java/utils/voice_intent_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

class HomeContent extends StatefulWidget {
  const HomeContent({super.key});

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isStartingRecord = false;
  bool _wantsToStop = false;

  int _currentStreamId = 0;

  late AnimationController _waveController;
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  final List<String> _pendingImages = [];

  // final String _baseUrl = "http://10.0.2.2:9000";
  // final String _baseUrl = "http://127.0.0.1:9000";
  final String _baseUrl = "http://10.96.97.231:9000";

  final List<Map<String, dynamic>> _messages = [
    {"role": "ai", "content": "您好！我是帮帮，有什么可以帮您？"},
  ];

  final StreamController<String> _aiStreamController = StreamController<String>.broadcast();

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 后端可能返回 { code, data } 或直接业务字段
  Map<String, dynamic> _unwrapApiDataMap(Map<String, dynamic> decoded) {
    final code = decoded['code'];
    if (code != null && code != 200) {
      throw Exception(decoded['message']?.toString() ?? '请求失败');
    }
    final inner = decoded['data'];
    if (inner is Map) {
      return Map<String, dynamic>.from(inner as Map);
    }
    if (inner is String && inner.trim().startsWith('{')) {
      try {
        final parsed = jsonDecode(inner);
        if (parsed is Map) return Map<String, dynamic>.from(parsed as Map);
      } catch (_) {}
    }
    return decoded;
  }

  /// 解析 /parse-audio 等非 SSE 的 JSON：更新用户识别文案、AI 回复、TTS、意图
  Future<void> _applyVoiceChatPayload(Map<String, dynamic> raw, int myStreamId) async {
    if (myStreamId != _currentStreamId) return;

    final recognized = (raw['recognizedText'] ?? raw['recognized_text'] ?? raw['text'] ?? '').toString();
    final feedback = (raw['voiceFeedback'] ?? raw['reply'] ?? raw['message'] ?? '').toString();
    final audioUrl = (raw['audioUrl'] ?? raw['audio_url'] ?? '').toString();
    final action = raw['action']?.toString();
    Map<String, dynamic> params = {};
    if (raw['params'] is Map) {
      params = Map<String, dynamic>.from(raw['params'] as Map);
    }

    setState(() {
      final lastUserIdx = _messages.lastIndexWhere((m) => m['role'] == 'user');
      if (lastUserIdx != -1) {
        if (recognized.isNotEmpty) {
          _messages[lastUserIdx]['content'] = recognized;
        } else if (_messages[lastUserIdx]['content'] == '[正在倾听...]') {
          _messages[lastUserIdx]['content'] = '（未识别到语音内容）';
        }
      }
      final display = feedback.isNotEmpty ? feedback : '（暂无文字回复）';
      if (_messages.isNotEmpty && _messages.last['role'] == 'ai') {
        _messages.last['content'] = display;
      }
      _aiStreamController.add(display);
    });
    _scrollToBottom();

    // 💡 修复：强制清空缓存并明确指定 MIME 类型
    if (audioUrl.isNotEmpty && myStreamId == _currentStreamId) {
      try {
        // 先停掉可能卡死的旧流
        await _audioPlayer.stop();
        // 在 URL 后面加个时间戳，彻底打破 Android 底层对同一个 URL 的玄学缓存
        String antiCacheUrl = "$_baseUrl$audioUrl${audioUrl.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}";

        debugPrint('🔊 准备播放音频: $antiCacheUrl');

        // 明确告诉 Flutter 这是 mp3 格式
        await _audioPlayer.play(UrlSource(antiCacheUrl, mimeType: 'audio/mpeg'));
      } catch (e) {
        debugPrint('TTS 播放失败: $e');
      }
    }

    if (action != null && action.isNotEmpty && myStreamId == _currentStreamId) {
      await VoiceIntentHandler.handle(action: action, params: params);
    }
  }

  void _interruptAI() {
    _currentStreamId++;
    _audioPlayer.stop();

    if (_isProcessing) {
      setState(() {
        _isProcessing = false;
        if (_messages.isNotEmpty && _messages.last['role'] == 'ai') {
          String content = _messages.last['content'];
          if (content.isEmpty) {
            _messages.last['content'] = "[已打断思考]";
            _aiStreamController.add("[已打断思考]");
          } else if (!content.endsWith("[已打断]")) {
            _messages.last['content'] = "$content [已打断]";
            _aiStreamController.add("$content [已打断]");
          }
        }
      });
      _scrollToBottom();
    }
  }

  Future<void> _handleStreamResponse(dynamic responseBody, {List<String>? imagePaths}) async {
    _currentStreamId++;
    final int myStreamId = _currentStreamId;

    setState(() {
      _isProcessing = true;
      _messages.add({"role": "ai", "content": ""});
    });
    _scrollToBottom();

    String currentDisplay = "";
    String buffer = "";
    bool hasReceivedData = false;
    // ⭐ 流超时兜底：15秒无数据则认为流异常，强制关闭
    Timer? streamTimeout;
    void resetTimeout() {
      streamTimeout?.cancel();
      streamTimeout = Timer(const Duration(seconds: 15), () {
        if (myStreamId == _currentStreamId && !hasReceivedData) {
          debugPrint("⚠️ 流接收超时（15s），强制结束");
          _currentStreamId++; // 失效当前流
        }
      });
    }
    resetTimeout();

    try {
      final Stream<List<int>> byteStream = (responseBody.stream as Stream).cast<List<int>>();

      await for (final String data in byteStream.transform(utf8.decoder)) {
        if (myStreamId != _currentStreamId) break;

        resetTimeout(); // 每收到数据就重置超时
        buffer += data;
        List<String> lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (String line in lines) {
          if (myStreamId != _currentStreamId) break;

          if (line.startsWith('data:')) {
            hasReceivedData = true;
            String jsonStr = line.substring(5).trim();
            if (jsonStr.isEmpty) continue;

            try {
              var jsonData = jsonDecode(jsonStr);

              if (jsonData['type'] == 'recognized') {
                setState(() {
                  int lastUserIdx = _messages.lastIndexWhere((m) => m['role'] == 'user');
                  if (lastUserIdx != -1) {
                    _messages[lastUserIdx]['content'] = jsonData['content'];
                  }
                });
              } else if (jsonData['type'] == 'text') {
                currentDisplay += jsonData['content'];
                if (myStreamId == _currentStreamId) {
                  _aiStreamController.add(currentDisplay);
                  setState(() => _messages.last["content"] = currentDisplay);
                  _scrollToBottom();
                }
              } else if (jsonData['type'] == 'meta') {
                String audioUrl = jsonData['audioUrl'] ?? "";
                String action = jsonData['action'] ?? "";
                var params = jsonData['params'] ?? {};

                // ⭐ 立即执行 action（不等 TTS 生成）
                if (action.isNotEmpty && myStreamId == _currentStreamId) {
                  // 异步执行，不阻塞后续 TTS 播放
                  VoiceIntentHandler.handle(
                    action: action,
                    params: params is Map ? Map<String, dynamic>.from(params as Map) : <String, dynamic>{},
                  );
                }

                // 💡 修复 2：如果后端 meta 里面直接就带了 audioUrl（比如非图片快速流），直接播放
                if (audioUrl.isNotEmpty && myStreamId == _currentStreamId) {
                  try {
                    await _audioPlayer.play(UrlSource("$_baseUrl$audioUrl"));
                  } catch (e) {
                    debugPrint("TTS 播放失败: $e");
                  }
                }
              }
              // 💡 修复 3：新增对 ttsReady 事件的处理。这是你后端 Controller 最新修改后，用于异步回调音频地址的事件。
              // 💡 修复：强制清空缓存并明确指定 MIME 类型
              else if (jsonData['type'] == 'ttsReady') {
                String audioUrl = jsonData['audioUrl'] ?? "";
                if (audioUrl.isNotEmpty && myStreamId == _currentStreamId) {
                  try {
                    await _audioPlayer.stop();
                    String antiCacheUrl = "$_baseUrl$audioUrl${audioUrl.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}";

                    debugPrint('🔊 收到 ttsReady，准备播放: $antiCacheUrl');

                    await _audioPlayer.play(UrlSource(antiCacheUrl, mimeType: 'audio/mpeg'));
                  } catch (e) {
                    debugPrint("收到 ttsReady，但 TTS 播放失败: $e");
                  }
                }
              }
            } catch (e) {
              debugPrint("SSE 流解析片段异常: $e");
            }
          }
        }
      }

      // 后端若返回整段 JSON（非 SSE），在此解析
      if (!hasReceivedData) {
        final trimmed = buffer.trim();
        if (trimmed.isNotEmpty) {
          try {
            final decoded = jsonDecode(trimmed);
            if (decoded is String) {
              await _applyVoiceChatPayload({'voiceFeedback': decoded, 'recognizedText': ''}, myStreamId);
            } else if (decoded is Map) {
              final payload = _unwrapApiDataMap(Map<String, dynamic>.from(decoded as Map));
              await _applyVoiceChatPayload(payload, myStreamId);
            }
          } catch (e) {
            debugPrint('非 SSE 响应解析失败: $e');
            // 后端偶发直接返回纯文本（非 JSON）
            if (trimmed.isNotEmpty &&
                !trimmed.startsWith('{') &&
                !trimmed.startsWith('[') &&
                !trimmed.startsWith('<')) {
              await _applyVoiceChatPayload({'voiceFeedback': trimmed, 'recognizedText': ''}, myStreamId);
            } else if (mounted && myStreamId == _currentStreamId) {
              setState(() {
                if (_messages.isNotEmpty && _messages.last['role'] == 'ai') {
                  _messages.last['content'] = '回复解析失败，请稍后再试。($e)';
                }
              });
            }
          }
        }
      }

    } catch (e) {
      debugPrint("网络流读取断开: $e");
      rethrow;
    } finally {
      streamTimeout?.cancel();
      if (mounted && myStreamId == _currentStreamId) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _startRecording() async {
    _interruptAI();
    if (_isRecording || _isStartingRecord) return;

    _isStartingRecord = true;
    _wantsToStop = false;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _isStartingRecord = false;
      return;
    }

    final directory = await getTemporaryDirectory();
    final filePath = '${directory.path}/record.wav';

    await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 8000), path: filePath);

    _isStartingRecord = false;

    if (_wantsToStop) {
      await _recorder.stop();
      return;
    }

    setState(() => _isRecording = true);
    _waveController.repeat();
  }

  Future<void> _stopRecordingAndUpload() async {
    if (_isStartingRecord) {
      _wantsToStop = true;
      return;
    }
    if (!_isRecording) return;

    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });
    _waveController.stop();

    final path = await _recorder.stop();
    if (path == null) {
      setState(() => _isProcessing = false);
      return;
    }

    List<String> imagesToSend = List.from(_pendingImages);
    setState(() => _pendingImages.clear());

    setState(() {
      _messages.add({
        "role": "user",
        "content": "[正在倾听...]",
        "imagePaths": imagesToSend
      });
    });
    _scrollToBottom();

    try {
      final formData = FormData();
      formData.fields.add(MapEntry("voiceId", UserProfileManager().currentVoiceId));

      formData.files.add(MapEntry("file", await MultipartFile.fromFile(path, filename: "record.wav")));
      for (int i = 0; i < imagesToSend.length; i++) {
        formData.files.add(MapEntry("imageFiles", await MultipartFile.fromFile(imagesToSend[i], filename: "image_$i.jpg")));
      }

      var responseBody = await ApiClient().post(
          '/api/chat/parse-audio',
          data: formData,
          options: Options(responseType: ResponseType.stream)
      );
      await _handleStreamResponse(responseBody);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          int lastUserIdx = _messages.lastIndexWhere((m) => m['role'] == 'user');
          if (lastUserIdx != -1 && _messages[lastUserIdx]['content'] == "[正在倾听...]") {
            _messages[lastUserIdx]['content'] = "[发送失败]";
          }
          _messages.add({"role": "ai", "content": "抱歉，由于网络波动断开了。内部错误: $e"});
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _sendImagesOnly() async {
    _interruptAI();

    if (_pendingImages.isEmpty) return;

    setState(() => _isProcessing = true);
    List<String> imagesToSend = List.from(_pendingImages);
    setState(() => _pendingImages.clear());

    setState(() {
      _messages.add({"role": "user", "content": "[发送了图片]", "imagePaths": imagesToSend});
    });
    _scrollToBottom();

    try {
      final formData = FormData();
      formData.fields.add(MapEntry("voiceId", UserProfileManager().currentVoiceId));

      for (int i = 0; i < imagesToSend.length; i++) {
        formData.files.add(MapEntry("imageFiles", await MultipartFile.fromFile(imagesToSend[i], filename: "img_$i.jpg")));
      }

      var responseBody = await ApiClient().post(
          '/api/chat/upload-image',
          data: formData,
          options: Options(responseType: ResponseType.stream)
      );
      await _handleStreamResponse(responseBody);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _messages.add({"role": "ai", "content": "图片发送失败，请检查网络或后端服务器状态。内部错误: $e"});
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _handleCameraAction() async {
    _interruptAI();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16.0), child: Text("添加图片", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blueAccent),
              title: const Text("拍一张"),
              onTap: () async {
                Navigator.pop(context);
                final image = await ImagePicker().pickImage(source: ImageSource.camera);
                if (image != null) setState(() => _pendingImages.add(image.path));
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text("从相册选择 (可多选)"),
              onTap: () async {
                Navigator.pop(context);
                final images = await ImagePicker().pickMultiImage();
                if (images.isNotEmpty) setState(() => _pendingImages.addAll(images.map((e) => e.path)));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _waveController.dispose();
    _scrollController.dispose();
    _aiStreamController.close();
    _recorder.dispose();
    _audioPlayer.dispose();
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
                        builder: (context, snapshot) {
                          return _buildChatBubble({"role": "ai", "content": snapshot.data ?? ""}, isAi);
                        }
                    );
                  }
                  return _buildChatBubble(msg, isAi);
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

        if (_pendingImages.isNotEmpty) _buildPendingImagesTray(),

        Padding(
          padding: const EdgeInsets.only(bottom: 160, left: 20, right: 20, top: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: sideBoxWidth),
              const Spacer(),
              GestureDetector(
                onTapDown: (_) => _startRecording(),
                onTapUp: (_) => _stopRecordingAndUpload(),
                onTapCancel: () => _stopRecordingAndUpload(),
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
                          color: Colors.white,
                          shape: BoxShape.circle,
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

  Widget _buildPendingImagesTray() {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _pendingImages.length,
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(right: 12, top: 8),
                      width: 60, height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                        image: DecorationImage(image: FileImage(File(_pendingImages[index])), fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      right: 4, top: 0,
                      child: GestureDetector(
                        onTap: () => setState(() => _pendingImages.removeAt(index)),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sendImagesOnly,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(20)),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.send, color: Colors.white, size: 20),
                  SizedBox(height: 4),
                  Text("发图片", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> msg, bool isAi) {
    String text = msg['content'] ?? "";
    List<String> imagePaths = msg['imagePaths'] ?? [];
    if (msg['imagePath'] != null && imagePaths.isEmpty) imagePaths = [msg['imagePath']];

    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.only(bottom: 20, left: isAi ? 0 : 40, right: isAi ? 40 : 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isAi ? Colors.white : const Color(0xFFE0F2FE),
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomLeft: isAi ? const Radius.circular(0) : const Radius.circular(20),
            bottomRight: isAi ? const Radius.circular(20) : const Radius.circular(0),
          ),
          boxShadow: isAi ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)] : null,
        ),
        child: Column(
          crossAxisAlignment: isAi ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            if (imagePaths.isNotEmpty)
              Wrap(
                spacing: 8, runSpacing: 8,
                children: imagePaths.map((path) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(path), width: 120, height: 120, fit: BoxFit.cover),
                )).toList(),
              ),
            if (imagePaths.isNotEmpty && text.isNotEmpty) const SizedBox(height: 8),
            if (text.isNotEmpty)
              Text(text, style: const TextStyle(fontSize: AppFonts.titleMedium, height: 1.4, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _buildMicButton() {
    Color bgColor = _isRecording ? Colors.redAccent : Colors.blueAccent;
    String text = _isRecording ? "松开结束" : "按着说话";

    if (_isProcessing && !_isRecording) {
      bgColor = Colors.orangeAccent;
      text = "按住打断";
    } else if (!_isRecording && _pendingImages.isNotEmpty) {
      text = "按住提问";
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 130, height: 130,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: bgColor.withOpacity(0.4), blurRadius: 20)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mic, color: Colors.white, size: 42),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: AppFonts.bodyMedium, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ... SiriWavePainter 保持不变 ...
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