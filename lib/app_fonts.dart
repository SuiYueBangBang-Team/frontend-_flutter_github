import 'package:flutter/material.dart';

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

  void setAvatar(int index) {
    _avatarIndex = index;
    notifyListeners();
  }

  void setLanguage(int index) {
    _languageIndex = index;
    notifyListeners();
  }

  // 💡 修改点 1：统一存放头像、语言数据，并绑定对应的百炼大模型语音 ID (voiceId)
  static final List<Map<String, dynamic>> avatars = [
    {"name": "小女孩", "icon": Icons.auto_awesome, "voiceId": "longhuhu"},      // 龙小喵 (可爱童声)
    {"name": "小男孩", "icon": Icons.face, "voiceId": "longwangwang"},              // 暂用童声代替 (如有更适合男童的音色可替换)
    {"name": "小姐姐", "icon": Icons.face_3, "voiceId": "longxiaochun_v2"},        // 龙应甜 (甜美女生)
    {"name": "小哥哥", "icon": Icons.person, "voiceId": "longhan_v2"},             // 龙飞 (阳光男声)
    {"name": "老爷爷", "icon": Icons.elderly, "voiceId": "longlaobo"},         // 龙老铁 (稳重大叔/东北男声)
    {"name": "老奶奶", "icon": Icons.elderly_woman, "voiceId": "longlaoyi"},      // 龙婉 (温柔女声，暂代长辈女声)
  ];

  static final List<String> languages = [
    "普通话", "粤语", "四川话", "东北话", "客家话", "湖南话"
  ];

  // 快捷获取当前选中的图标
  IconData get currentAvatarIcon => avatars[_avatarIndex]["icon"];

  // 💡 修改点 2：新增快捷获取当前选中音色 ID 的方法，给接口请求使用
  String get currentVoiceId => avatars[_avatarIndex]["voiceId"] as String;
}