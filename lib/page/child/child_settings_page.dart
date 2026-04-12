import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // 用于调用相机
import 'package:dio/dio.dart'; // 用于构建 FormData
import 'package:phone_java/app_fonts.dart';
import 'package:phone_java/utils/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_cropper/image_cropper.dart'; // 引入裁剪库
import 'dart:io'; // 用于处理文件

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


  // 弹窗选择拍照或相册
  void _showAvatarPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("修改头像", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(context);
                _uploadAvatarTask(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.orange),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(context);
                _uploadAvatarTask(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  // 选图 -> 裁剪 -> 上传 -> 更新的完整流程
  Future<void> _uploadAvatarTask(ImageSource source) async {
    try {
      // 1. 调用 image_picker 选图 (获取原始图片)
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: source);
      if (pickedFile == null) return;

      // 调用 image_cropper 进行裁剪
      final CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path, // 传入原始图片路径
        uiSettings: [
          // Android 端设置
          AndroidUiSettings(
            toolbarTitle: '裁剪头像',
            toolbarColor: Colors.blueGrey,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square, // 初始化为 1:1
            lockAspectRatio: true, // 锁定比例，不能随意拉伸
            aspectRatioPresets: [CropAspectRatioPreset.square], // 💡 新版：强制 1:1 移到了这里
          ),
          // iOS 端设置
          IOSUiSettings(
            title: '裁剪头像',
            aspectRatioLockEnabled: true, // 锁定比例
            aspectRatioPresets: [CropAspectRatioPreset.square], // 💡 新版：强制 1:1 移到了这里
            doneButtonTitle: '完成',
            cancelButtonTitle: '取消',
          ),
        ],
      );

      // 如果用户取消了裁剪，整个流程终止
      if (croppedFile == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("正在上传头像...")));

      // 3. 构造 FormData 并上传图片 (💡 注意：这里使用的是裁剪后的 croppedFile)
      FormData formData = FormData.fromMap({
        // 从裁剪后的文件路径创建一个新的上传文件
        "file": await MultipartFile.fromFile(croppedFile.path, filename: "avatar.jpg"),
      });

      // 复用之前的图片上传接口
      var uploadRes = await ApiClient().post('/api/upload/image', data: formData);

      // 解析返回的图片 URL
      String newAvatarUrl = "";
      if (uploadRes != null) {
        newAvatarUrl = uploadRes is Map ? uploadRes['data'].toString() : uploadRes.toString();
      }

      if (newAvatarUrl.isEmpty || newAvatarUrl == "null") {
        throw Exception("获取上传后的图片地址失败");
      }

      // 4. 调用后端接口更新用户表中的 avatar 字段 (保持不变)
      await ApiClient().post('/api/auth/update-avatar', data: {
        "avatar": newAvatarUrl
      });

      // 5. 更新本地 SharedPreferences 和 UI (保持不变)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('avatarUrl', newAvatarUrl);

      setState(() {
        avatarUrl = newAvatarUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("头像修改成功")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("头像修改失败: $e")));
      }
    }
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
              String newName = editController.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("用户名不能为空")));
                return;
              }

              try {
                // 调用后端接口，修改昵称
                await ApiClient().post('/api/auth/update-nickname', data: {
                  "nickname": newName
                });

                // 只有后端 API 返回成功，才修改本地持久化存储
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('nickname', newName);

                setState(() {
                  nickname = newName;
                });

                if (mounted) {
                  Navigator.pop(context); // 关闭弹窗
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("昵称已修改")));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("修改失败: $e")));
                }
              }
            },
            child: const Text("确定", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // 💡 唤起人脸录入流程 (弹窗选择长辈 -> 拍照上传)
  Future<void> _handleFaceRegistration() async {
    try {
      // 1. 获取绑定的长辈列表 (💡 核心修复：请求设备关联接口，而不是通讯录接口！)
      var res = await ApiClient().get('/api/family/devices');
      List<dynamic> members = [];
      if (res != null) {
        members = res is List ? res : (res['data'] ?? []);
      }

      if (members.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("暂无绑定的长辈账号，请先在【家庭设备】页面添加绑定")));
        return;
      }

      if (!mounted) return;

      // 2. 弹窗让子女选择要录入的长辈
      var selectedMember = await showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (context) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("选择要录入人脸的关联长辈", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  ...members.map((m) => ListTile(
                    leading: const CircleAvatar(backgroundColor: Color(0xFFEFF6FF), child: Icon(Icons.person, color: Colors.blue)),
                    title: Text(m['name'] ?? "未知长辈"),
                    subtitle: Text("状态: ${m['status'] ?? '未知'}"), // 💡 显示设备在线状态
                    trailing: const Icon(Icons.camera_alt, color: Colors.grey),
                    onTap: () => Navigator.pop(context, m),
                  )),
                  const SizedBox(height: 10),
                ],
              ),
            );
          }
      );

      if (selectedMember == null) return; // 用户取消了选择

      // 3. 唤起手机相机 (使用前置)
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 80,
      );

      if (image == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("正在上传并录入长辈人脸...")));

      // 4. 上传至后端
      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(image.path, filename: "register_face.jpg"),
        "memberId": selectedMember['id'], // 传入选择的长辈关联ID
      });

      await ApiClient().post('/api/family/face/register', data: formData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("已成功为 [${selectedMember['name'] ?? '长辈'}] 录入人脸！"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("人脸录入失败: $e"), backgroundColor: Colors.red));
      }
    }
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
          // --- 1. 个人信息卡片 (仿照图片UI) ---
          _buildSettingCard(
            child: Column(
              children: [
                const SizedBox(height: 10),
                // 头像点击修改
                GestureDetector(
                  onTap: _showAvatarPicker, // 💡 绑定选图弹窗方法
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blueGrey.shade50,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
                      // 动态判断：如果有网络头像就显示，没有就显示本地默认图
                      image: avatarUrl.isNotEmpty
                          ? DecorationImage(
                        image: NetworkImage(avatarUrl),
                        fit: BoxFit.cover,
                      )
                          : const DecorationImage(
                        image: AssetImage("assets/images/avatar_ball.png"),
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

          // --- 2. 长辈关怀设置卡片 (💡 新增: 为长辈录入人脸入口) ---
          _buildSettingCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.family_restroom_rounded, color: Colors.blueAccent, size: 32),
                    const SizedBox(width: 12),
                    Expanded(child: Text("长辈关怀设置", style: TextStyle(fontSize: AppFonts.titleLarge, fontWeight: FontWeight.bold))),
                  ],
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.face_retouching_natural_rounded, color: Colors.orange, size: 24),
                  ),
                  title: const Text("为长辈录入人脸", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  subtitle: const Text("协助长辈设置刷脸快捷登录"),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Colors.grey),
                  onTap: () => _handleFaceRegistration(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),

          // --- 3. 字体调整卡片 (与父母端一致) ---
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

          // --- 4. 退出登录 ---
          _buildActionButton(label: "退出登录", icon: Icons.logout_rounded, color: Colors.redAccent, onTap: _handleLogout, isOutlined: true),
        ],
      ),
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