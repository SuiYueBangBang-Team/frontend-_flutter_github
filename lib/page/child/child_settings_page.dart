import 'package:flutter/material.dart';
import 'package:phone_java/app_fonts.dart';
import 'package:phone_java/utils/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChildSettingsPage extends StatefulWidget {
  const ChildSettingsPage({super.key});

  @override
  State<ChildSettingsPage> createState() => _ChildSettingsPageState();
}

class _ChildSettingsPageState extends State<ChildSettingsPage> {
  String nickname = "加载中...";
  String userPhone = "未登录";
  String avatarUrl = ""; // 后续用于接收网络头像图片

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    // 💡 修复点：使用 ?? "" 兜底，防止出现 type 'Null' is not a subtype of type 'String' 的报错
    setState(() {
      userPhone = prefs.getString('userPhone') ?? "未登录";
      nickname = prefs.getString('nickname') ?? "";
      avatarUrl = prefs.getString('avatarUrl') ?? "";
    });
  }

  // 修改昵称的弹窗
  void _showEditNicknameDialog() {
    TextEditingController editController = TextEditingController(text: nickname);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("修改用户名", style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: editController,
          decoration: InputDecoration(
            hintText: "请输入新的用户名",
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, elevation: 0),
            onPressed: () async {
              // 🔒 TODO: 后端对接 - 调用修改资料接口
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('nickname', editController.text);
              setState(() => nickname = editController.text);
              if (mounted) Navigator.pop(context);
            },
            child: const Text("确定", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    try {
      await ApiClient().post('/api/auth/logout');
    } catch (e) {
      debugPrint("退出接口调用异常: $e");
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('userId');
    await prefs.remove('userPhone');
    await prefs.remove('nickname');

    ApiClient.globalToken = null;
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), // 保持和父母端一致的边距
        children: [
          // --- 1. 新增：个人信息卡片 (仿照图片UI) ---
          _buildSettingCard(
            child: Column(
              children: [
                const SizedBox(height: 10),
                // 头像点击修改
                GestureDetector(
                  onTap: () {
                    // 🔒 TODO: 对接图片选择器与上传接口
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("触发修改头像功能")));
                  },
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blueGrey.shade50,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
                      // 玻璃球图片可以替换为你 assets 中的图片，或者 NetworkImage
                      image: const DecorationImage(
                        image: AssetImage("assets/images/avatar_ball.png"), // 请确保图片路径正确
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 用户名与修改图标
                GestureDetector(
                  onTap: _showEditNicknameDialog,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(nickname, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      const Icon(Icons.edit_square, color: Colors.black87, size: 22),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 底部电话/邮箱
                Text(
                  userPhone,
                  style: const TextStyle(fontSize: 16, color: Colors.grey, letterSpacing: 0.5),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
          const SizedBox(height: 15),

          // --- 2. 字体调整卡片 (与父母端一致) ---
          ListenableBuilder(
            listenable: FontManager(),
            builder: (context, child) {
              return _buildSettingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.format_size_rounded, color: Colors.blueAccent, size: 32),
                        const SizedBox(width: 12),
                        Expanded(child: Text("调整全局文字大小", style: TextStyle(fontSize: AppFonts.titleLarge, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Row(
                      children: [
                        const Text("较小", style: TextStyle(fontSize: 16), textScaler: TextScaler.noScaling),
                        Expanded(
                          child: Slider(
                            value: FontManager().scale,
                            min: 0.8, max: 1.4, divisions: 6,
                            activeColor: Colors.blueAccent,
                            onChanged: (double value) {
                              FontManager().setScale(value);
                              // 🔒 TODO: 调用配置同步接口，同步给父母端
                            },
                          ),
                        ),
                        const Text("特大", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold), textScaler: TextScaler.noScaling),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Center(child: Text("当前文字比例：${(FontManager().scale * 100).toInt()}%", style: const TextStyle(fontSize: AppFonts.bodyMedium, color: Colors.grey))),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 15),

          // --- 3. 个性化配置卡片 (与父母端完全一致，无护城河) ---
          ListenableBuilder(
            listenable: Listenable.merge([FontManager(), UserProfileManager()]),
            builder: (context, child) {
              return _buildSettingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.face_retouching_natural_rounded, color: Colors.blueAccent, size: 32),
                        const SizedBox(width: 12),
                        Expanded(child: Text("个性化配置 (双端同步)", style: TextStyle(fontSize: AppFonts.titleLarge, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text("选择帮帮形象", style: TextStyle(fontSize: AppFonts.bodyLarge, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 10),
                    _buildAvatarGrid(),

                    const SizedBox(height: 10),
                    Text("选择帮帮语言", style: TextStyle(fontSize: AppFonts.bodyLarge, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 10),
                    _buildLanguageGrid(),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 15),

          // --- 4. 退出登录 ---
          _buildActionButton(label: "退出登录", icon: Icons.logout_rounded, color: Colors.redAccent, onTap: _handleLogout, isOutlined: true),
        ],
      ),
    );
  }

  // 💡 完全沿用父母端的形象网格
  Widget _buildAvatarGrid() {
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: UserProfileManager.avatars.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      itemBuilder: (context, index) {
        bool selected = UserProfileManager().avatarIndex == index;
        return GestureDetector(
          onTap: () {
            UserProfileManager().setAvatar(index);
            // 🔒 TODO: 调用配置同步接口，同步给父母端
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? Colors.blueAccent : Colors.grey.shade300, width: selected ? 2.5 : 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: selected ? Colors.blueAccent : Colors.blueGrey.shade50,
                  child: Icon(UserProfileManager.avatars[index]["icon"], color: selected ? Colors.white : Colors.blueGrey, size: 24),
                ),
                const SizedBox(height: 8),
                Text(UserProfileManager.avatars[index]["name"], style: TextStyle(fontSize: AppFonts.bodySmall, color: selected ? Colors.blueAccent : Colors.black87)),
              ],
            ),
          ),
        );
      },
    );
  }

  // 💡 完全沿用父母端的语言网格
  Widget _buildLanguageGrid() {
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: UserProfileManager.languages.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, index) {
        bool selected = UserProfileManager().languageIndex == index;
        return GestureDetector(
          onTap: () {
            UserProfileManager().setLanguage(index);
            // 🔒 TODO: 调用配置同步接口，同步给父母端
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.blueAccent : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? Colors.blueAccent : Colors.grey.shade300),
            ),
            child: Text(
              UserProfileManager.languages[index],
              style: TextStyle(fontSize: AppFonts.bodySmall, color: selected ? Colors.white : Colors.black87),
            ),
          ),
        );
      },
    );
  }

  // 💡 完全沿用父母端的大边距卡片样式
  Widget _buildSettingCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 5))]
      ),
      child: child,
    );
  }

  // 💡 完全沿用父母端的大号按钮样式
  Widget _buildActionButton({required String label, required IconData icon, required Color color, required VoidCallback onTap, bool isOutlined = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 85,
        decoration: BoxDecoration(
          color: isOutlined ? Colors.transparent : color,
          borderRadius: BorderRadius.circular(25),
          border: isOutlined ? Border.all(color: color, width: 2.5) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isOutlined ? color : Colors.white, size: 32),
            const SizedBox(width: 15),
            Text(label, style: TextStyle(color: isOutlined ? color : Colors.white, fontSize: AppFonts.titleLarge, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}