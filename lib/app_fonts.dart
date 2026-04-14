import 'package:flutter/material.dart';
import 'package:phone_java/utils/api_client.dart'; // 💡 引入请求客户端
import 'package:shared_preferences/shared_preferences.dart';
//  全局字体管理器
class FontManager extends ChangeNotifier {
  static final FontManager _instance = FontManager._internal();
  factory FontManager() => _instance;
  FontManager._internal();

  double _scale = 1.0;
  double get scale => _scale;

  void setScale(double newScale) {
    if (newScale >= 0.8 && newScale <= 1.4) {
      _scale = newScale;
      notifyListeners();
    }
  }
}

class AppFonts {
  static const double titleLarge = 26.0;
  static const double titleMedium = 24.0;
  static const double bodyLarge = 20.0;
  static const double bodyMedium = 19.0;
  static const double bodySmall = 17.0;
  static const double caption = 14.0;
}

//  全局用户信息管理器 (同步头像与语言)
class UserProfileManager extends ChangeNotifier {
  static final UserProfileManager _instance = UserProfileManager._internal();
  factory UserProfileManager() => _instance;
  UserProfileManager._internal();

  // 默认选中项：0 (小女孩, 普通话)
  int _avatarIndex = 0;
  int _languageIndex = 0;

  int get avatarIndex => _avatarIndex;
  int get languageIndex => _languageIndex;

  void setAvatar(int index) async {
    if (_avatarIndex == index) return;
    _avatarIndex = index;
    notifyListeners();

    try {
      String newVoiceId = currentVoiceId;
      // 1. 同步给云端数据库
      await ApiClient().post('/api/auth/update-voice', data: {"voiceId": newVoiceId});

      // 2. 💡 新增：同步保存到手机本地
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('voiceId', newVoiceId);

      debugPrint("✅ 已同步新音色到云端和本地: $newVoiceId");
    } catch (e) {
      debugPrint("❌ 同步音色到云端失败: $e");
    }
  }

  void setLanguage(int index) {
    _languageIndex = index;
    notifyListeners();
  }

  // 💡 修改点 1：统一存放头像、语言数据，并绑定对应的百炼大模型语音 ID (voiceId)
  static final List<Map<String, dynamic>> avatars = [
    {"name": "小女孩", "icon": Icons.face_3, "voiceId": "longhuhu"},      // 龙小喵 (可爱童声)
    {"name": "小男孩", "icon": Icons.face, "voiceId": "longwangwang"},              // 暂用童声代替 (如有更适合男童的音色可替换)
    {"name": "小姐姐", "icon": Icons.face_4, "voiceId": "longxiaochun_v2"},        // 龙应甜 (甜美女生)
    {"name": "小哥哥", "icon": Icons.face_6, "voiceId": "longhan_v2"},             // 龙飞 (阳光男声)
    {"name": "老爷爷", "icon": Icons.elderly, "voiceId": "longlaobo"},         // 龙老铁 (稳重大叔/东北男声)
    {"name": "老奶奶", "icon": Icons.elderly_woman, "voiceId": "longlaoyi"},      // 龙婉 (温柔女声，暂代长辈女声)
  ];

  static final List<String> languages = [
    "普通话", "粤语"
  ];

  // 快捷获取当前选中的图标
  IconData get currentAvatarIcon => avatars[_avatarIndex]["icon"];

  // 💡 修改点 2：新增快捷获取当前选中音色 ID 的方法，给接口请求使用
  String get currentVoiceId => avatars[_avatarIndex]["voiceId"] as String;

  // 💡 2. 新增方法：登录成功后，根据后端传回来的 voiceId，自动选中对应的头像
  void syncVoiceIdFromBackend(String backendVoiceId) {
    int index = avatars.indexWhere((avatar) => avatar["voiceId"] == backendVoiceId);
    if (index != -1) {
      _avatarIndex = index;
      notifyListeners(); // 更新 UI，高亮长辈上次选的那个头像
      debugPrint("✅ 已根据云端数据恢复长辈头像选择");
    }
  }

  // 💡 1. 新增：App 启动时从本地读取上次保存的音色
  Future<void> loadLocalVoiceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedVoiceId = prefs.getString('voiceId');
    if (savedVoiceId != null) {
      syncVoiceIdFromBackend(savedVoiceId); // 复用之前的恢复方法
      debugPrint("✅ App 启动，已从本地缓存恢复长辈音色: $savedVoiceId");
    }
  }
}