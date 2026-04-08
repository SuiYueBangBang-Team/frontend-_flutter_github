import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:phone_java/page/onboarding/FaceLoginPage.dart'; // 💡 引入刷脸页面
class QuickLoginPage extends StatefulWidget {
  const QuickLoginPage({super.key});

  @override
  State<QuickLoginPage> createState() => _QuickLoginPageState();
}

class _QuickLoginPageState extends State<QuickLoginPage> {
  bool agree = false;

  void _handleQuickLogin(String role) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("测试环境已为您跳转至短信登录"),
        duration: Duration(seconds: 1),
      ),
    );

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        //  核心修改：带着 role 继续跳
        Navigator.pushNamed(context, '/phone_input', arguments: role);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    //  核心修改：接收上一个页面传来的角色参数，默认是长辈
    final role = ModalRoute.of(context)?.settings.arguments as String? ?? 'ELDER';
    final isChild = role == 'CHILD';

    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            /// 顶部标题
            GestureDetector(
              //  核心修改：统一改成 pop 返回上一页（选角色页）
              onTap: () => Navigator.pop(context),
              child: Center(
                child: Text(
                  //  核心修改：动态改变标题
                  isChild ? "子女端登录" : "长辈端登录",
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 50),

            /// 号码显示区
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  const Opacity(
                    opacity: 0,
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.edit_note_rounded, size: 30),
                    ),
                  ),
                  const Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        "138 **** 8888",
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_note_rounded, color: Colors.blueAccent, size: 30),
                    //  核心修改：带着 role 跳去验证码页
                    onPressed: () => Navigator.pushNamed(context, '/phone_input', arguments: role),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            /// 💡 新增：如果是长辈端，优先显示刷脸登录按钮
            if (!isChild) ...[
              SizedBox(
                width: double.infinity,
                height: 65,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.face_retouching_natural_rounded, size: 30),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    elevation: 5,
                    shadowColor: Colors.blueAccent.withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: () {
                    // 跳转到独立的人脸识别页面
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const FaceLoginPage()));
                  },
                  label: const Text(
                    "推荐：刷脸极速登录",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            /// 一键登录按钮
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: agree ? Colors.blueAccent : Colors.grey[300],
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                //  核心修改：传入 role
                onPressed: agree ? () => _handleQuickLogin(role) : null,
                child: Text(
                  "一键登录",
                  style: TextStyle(
                    color: agree ? Colors.white : Colors.grey[600],
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 60),

            /// 第三方登录
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSocialIcon(Icons.wechat, Colors.green, "微信"),
                _buildSocialIcon(Icons.person_rounded, Colors.blue, "QQ"),
                _buildSocialIcon(Icons.more_horiz_rounded, Colors.grey, "更多"),
              ],
            ),

            const SizedBox(height: 40),

            /// 用户协议
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Checkbox(
                  value: agree,
                  activeColor: Colors.blueAccent,
                  shape: const CircleBorder(),
                  onChanged: (v) => setState(() => agree = v!),
                ),
                const Text("我已阅读并同意", style: TextStyle(color: Colors.grey, fontSize: 14)),
                const Text(
                  "《用户协议》",
                  style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialIcon(IconData icon, Color color, String label) {
    return Column(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color, size: 30),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      ],
    );
  }
}