import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';
// 工具类
import 'package:phone_java/utils/api_client.dart';
import 'app_fonts.dart';

// 页面类 - 引导与登录
import 'package:phone_java/page/onboarding/RoleSelectionPage.dart';
import 'package:phone_java/page/onboarding/QuickLoginPage.dart';
import 'package:phone_java/page/onboarding/PhoneInputPage.dart';
import 'package:phone_java/page/onboarding/AvatarSelectionPage.dart';

// 页面类 - 长辈端主页
import 'index_page.dart';

// 页面类 - 子女端主页
//  注意：请确保你已经按照之前的建议在 lib/page/child/ 目录下创建了该文件
import 'package:phone_java/page/child/child_index_page.dart';

import 'package:phone_java/page/child/child_comm_post_create.dart';
import 'package:phone_java/page/child/child_comm_post_myself.dart';

//  1. 全局 NavigatorKey
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

//  2. 定义全局初始路由变量
String initialRoute = '/';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //  必须在调用任何接口前同意隐私政策
  BMFMapSDK.setAgreePrivacy(true);

  //  可以在 Dart 侧再次初始化 SDK（特别是兼容 iOS 平台），Android 平台也会以这里为主兜底
  BMFMapSDK.setApiKeyAndCoordType(
      'gOk4AIifU6VZZTRrwxoMlWOXyjt1DCPX', BMF_COORD_TYPE.BD09LL);



  // 1. 读取本地缓存
  final prefs = await SharedPreferences.getInstance();
  final savedToken = prefs.getString('token');
  final savedRole = prefs.getString('role');

  // 2. 判断是否存在有效的 Token
  if (savedToken != null && savedToken.isNotEmpty) {
    // 将读取到的 token 赋值给 ApiClient，这样后续的网络请求都会自动带上头信息
    ApiClient.globalToken = savedToken;

    //  核心逻辑：自动登录时，根据角色决定去哪个主页
    if (savedRole == 'CHILD') {
      initialRoute = '/child_index'; // 跳转到子女端主页
    } else {
      initialRoute = '/home';        // 跳转到长辈端主页
    }
  } else {
    // 如果没有 Token，才进入初始的角色选择/登录页面
    initialRoute = '/';
  }

  // 💡 新增：通知状态管理器立刻去读取本地保存的音色
  await UserProfileManager().loadLocalVoiceId();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    //  使用 ListenableBuilder 监听 FontManager 实现全局字体缩放
    return ListenableBuilder(
      listenable: FontManager(),
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: '岁悦帮帮',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primaryColor: Colors.blueAccent,
            useMaterial3: true,
            fontFamily: 'PingFang SC',
          ),

          //  核心拦截器：通过 MediaQuery 实现全局比例缩放
          builder: (context, widget) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(FontManager().scale),
              ),
              child: widget!,
            );
          },

          //  使用动态确定的初始路由
          initialRoute: initialRoute,

          routes: {
            // 公共引导路由
            '/': (context) => const RoleSelectionPage(),
            '/login': (context) => const QuickLoginPage(),
            '/phone_input': (context) => const PhoneInputPage(),

            // 长辈端专属
            '/avatar': (context) => const AvatarSelectionPage(),
            '/home': (context) => const IndexPage(),

            // 子女端专属
            '/child_index': (context) => const ChildIndexPage(),

            //  新增：社区相关路由
            '/createPostPage': (context) => const CreatePostPage(),
            '/myPostPage': (context) => const MyPostPage(),
          },
        );
      },
    );
  }
}