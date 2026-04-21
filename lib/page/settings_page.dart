import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:phone_java/app_fonts.dart';
import 'package:phone_java/page/emergency_page.dart';
import 'package:phone_java/utils/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _handleLogout() async {
    //  1. 新增：通知后端销毁 Redis 中的 Token
    try {
      await ApiClient().post('/api/auth/logout');
    } catch (e) {
      // 就算网络不好或者后端报错，也无所谓，继续往下走清理本地
      print("退出接口调用异常: $e");
    }

    //  2. 彻底清理缓存和内存
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('userId');
    await prefs.remove('userPhone');

    ApiClient.globalToken = null;

    //  3. 返回登录页
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }
  Future<void> _handleSwitchAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId') ?? '';
    if (!mounted) {
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("当前用户"),
        content: Text(userId.isEmpty ? "未登录" : "UserId：$userId"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("确定")),
        ],
      ),
    );
  }

  Future<String> _loadUserPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userPhone') ?? "未登录";
  }

  void _navigateToSosTest() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const EmergencyPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), // 恢复舒适的底部留白
        children: [
          // --- 1. 字体调整卡片 ---
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
                            onChanged: (double value) => FontManager().setScale(value),
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

          // --- 2. 形象与语言选择卡片 (优化点在此) ---
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
                        Expanded(child: Text("个性化配置", style: TextStyle(fontSize: AppFonts.titleLarge, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text("选择帮帮形象", style: TextStyle(fontSize: AppFonts.bodyLarge, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 10),
                    //  调整点：去掉网格自带的边距
                    _buildAvatarGrid(),

                    const SizedBox(height: 10),
                    Text("选择帮帮语言", style: TextStyle(fontSize: AppFonts.bodyLarge, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 10),
                    // 💡 修改点：调用新的左右布局方法
                    _buildLanguageLayout(),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 15),

          // --- 3. 紧急求助卡片 ---
          _buildSettingCard(
            child: InkWell(
              onTap: _navigateToSosTest,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.sos_rounded, color: Colors.red, size: 35),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("紧急求助测试", style: TextStyle(fontSize: AppFonts.titleLarge, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text("点击进入模拟报警流程", style: TextStyle(fontSize: AppFonts.bodyLarge, color: Colors.black54)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 26, color: Colors.black26),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),

          // --- 5. 账号操作 ---
          FutureBuilder<String>(
            future: _loadUserPhone(),
            builder: (context, snapshot) {
              final phone = snapshot.data ?? "未登录";
              return _buildSettingCard(
                child: InkWell(
                  onTap: _handleSwitchAccount,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.switch_account_rounded, color: Colors.blueAccent, size: 30),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("当前账号", style: TextStyle(fontSize: AppFonts.titleLarge, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(phone, style: TextStyle(fontSize: AppFonts.bodyLarge, color: Colors.black54)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 22, color: Colors.black26),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 15),
          _buildActionButton(label: "退出登录", icon: Icons.logout_rounded, color: Colors.redAccent, onTap: _handleLogout, isOutlined: true),
        ],
      ),
    );
  }

  //  重点修改：设置 padding 为 EdgeInsets.zero
  Widget _buildAvatarGrid() {
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero, //  强制去除护城河
      physics: const NeverScrollableScrollPhysics(),
      itemCount: UserProfileManager.avatars.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.9, // 恢复原本舒适比例
      ),
      itemBuilder: (context, index) {
        bool selected = UserProfileManager().avatarIndex == index;
        return GestureDetector(
          onTap: () => UserProfileManager().setAvatar(index),
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

  //  重点修改：设置 padding 为 EdgeInsets.zero
  Widget _buildLanguageLayout() {
    return Row(
      children: [
        Expanded(child: _buildSettingsLanguageItem(0)),
        const SizedBox(width: 15),
        Expanded(child: _buildSettingsLanguageItem(1)),
      ],
    );
  }

  Widget _buildSettingsLanguageItem(int index) {
    bool selected = UserProfileManager().languageIndex == index;
    return GestureDetector(
      onTap: () => UserProfileManager().setLanguage(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 48, // 适合设置页面的高度
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.blueAccent : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Colors.blueAccent : Colors.grey.shade300, width: selected ? 2 : 1),
        ),
        child: Text(
          UserProfileManager.languages[index],
          style: TextStyle(
              fontSize: AppFonts.bodySmall,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? Colors.white : Colors.black87
          ),
        ),
      ),
    );
  }



  Widget _buildSettingCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(25), // 恢复原本的大内边距
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 5))]),
      child: child,
    );
  }

  Widget _buildActionButton({required String label, required IconData icon, required Color color, required VoidCallback onTap, bool isOutlined = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 85, // 恢复原本的按钮高度
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