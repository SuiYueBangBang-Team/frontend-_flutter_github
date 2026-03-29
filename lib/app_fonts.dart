import 'package:flutter/material.dart';

// 💡 全局字体管理器
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

// 💡 新增：全局用户信息管理器 (同步头像与语言)
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

  // 💡 统一存放头像和语言数据，避免各个页面重复写
  static final List<Map<String, dynamic>> avatars = [
    {"name": "小女孩", "icon": Icons.auto_awesome},
    {"name": "小男孩", "icon": Icons.face},
    {"name": "小姐姐", "icon": Icons.face_3},
    {"name": "小哥哥", "icon": Icons.person},
    {"name": "老爷爷", "icon": Icons.elderly},
    {"name": "老奶奶", "icon": Icons.elderly_woman},
  ];

  static final List<String> languages = [
    "普通话", "粤语", "四川话", "东北话", "客家话", "湖南话"
  ];

  // 快捷获取当前选中的图标
  IconData get currentAvatarIcon => avatars[_avatarIndex]["icon"];
}