import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../utils/api_client.dart'; // 引入请求客户端
import '../../utils/location_service.dart'; // 引入单例服务

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final TextEditingController contentController = TextEditingController();
  final TextEditingController locationSearchController = TextEditingController();

  String? locationName;
  String? topicName;
  String cityName = "";
  String provinceName = "";
  String districtName = "";
  bool showLocationPanel = false;

  List<Map> locationList = [];
  List<Map> originLocationList = [];
  List<String> topicList = [];
  List<String> imageList = []; // 存放上传成功的图片URL

  @override
  void initState() {
    super.initState();
    loadCurrentLocation();
    loadRecommendLocation();
    loadTopicList();
    // 删除 loadCurrentCity() 的调用，已由 loadCurrentLocation 统一处理
  }

  /// 修改后的真实定位方法
  loadCurrentLocation() async {
    setState(() {
      locationName = "获取当前地址中...";
    });

    // 调用新封装的精简定位方法
    var locData = await LocationService().getSimplifiedLocation();

    if (mounted) {
      setState(() {
        // locationName 只显示“XX市 · XX区”或“XX县 · XX村”
        locationName = locData['display'];
        // 保存完整的省市区信息，用于发帖字段
        provinceName = locData['province'] ?? "";
        cityName = locData['city'] ?? "";
        districtName = locData['district'] ?? "";
      });
    }
  }

  /// 删除旧的 loadCurrentCity 方法，已并入 loadCurrentLocation

  /// 推荐定位列表
  loadRecommendLocation() async {
    originLocationList = [
      {"name": "广州应用科技学院（肇庆校区）", "distance": "1.0km", "address": "鼎湖区"},
      {"name": "莲花广场", "distance": "1.3km", "address": "鼎湖区"},
      {"name": "广科交流中心", "distance": "123m", "address": "鼎湖区"},
      {"name": "葫芦山风景区", "distance": "1.9km", "address": "鼎湖区"},
      {"name": "鼎湖万达广场", "distance": "2.5km", "address": "鼎湖区"},
      {"name": "鼎湖山景区入口", "distance": "3.1km", "address": "鼎湖区"},
    ];
    setState(() {
      locationList = originLocationList;
    });
  }

  /// 搜索定位
  searchLocation(keyword) async {
    if (keyword.isEmpty) {
      setState(() {
        locationList = originLocationList;
      });
      return;
    }
    List<Map> nearbyList = originLocationList.where((item) {
      return item["name"].contains(keyword);
    }).toList();
    setState(() {
      locationList = nearbyList;
    });
  }

  /// 话题列表
  loadTopicList() async {
    setState(() {
      topicList = ["育儿经验", "健康守护", "家庭关系", "长辈陪伴"];
    });
  }

  ///  真实调用相册并上传图片到后端
  uploadImage() async {
    final picker = ImagePicker();
    // 1. 唤起相册
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return; // 用户取消选择

    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("正在上传图片...")));

      // 2. 构造上传文件的数据表单
      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(image.path, filename: "upload.jpg"),
      });

      // 3. 调用后端上传接口
      var response = await ApiClient().post('/api/upload/image', data: formData);

      // 假设后端直接返回图片的 URL 字符串
      String imageUrl = response.toString();

      // 4. 将 URL 加入列表并刷新 UI
      setState(() {
        imageList.add(imageUrl);
      });

      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("图片上传成功")));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("图片上传失败: $e")));
    }
  }

  ///  真实的发布帖子核心函数
  publishPost() async {
    if (contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请输入帖子内容")));
      return;
    }

    if (locationName == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请选择定位后再发布")));
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("正在发布...")));

      // 将图片列表拼接成用逗号分隔的字符串，存入数据库的 images 字段
      String imagesStr = imageList.join(',');

      // 真实调用后端发帖接口
      await ApiClient().post('/api/community/post/create', data: {
        "content": contentController.text.trim(),
        "images": imagesStr,
        "location": locationName,
        "province": provinceName,
        "city": cityName,
        "district": districtName,
      });

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("发布成功"), duration: Duration(seconds: 1)));
        // 跳转回社区页面
        Navigator.pop(context);
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("发布失败: $e")));
    }
  }

  /// 话题选择器
  showTopicSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView(
          children: topicList.map((topic) {
            return ListTile(
              title: Text(topic),
              onTap: () {
                setState(() => topicName = topic);
                Navigator.pop(context);
              },
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            /// 顶部栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text("取消", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  GestureDetector(
                    onTap: publishPost,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                      decoration: BoxDecoration(
                        color: contentController.text.isEmpty
                            ? const Color(0xFFE5E5E5)
                            : const Color(0xFF4A7BFF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text("发表", style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),

            /// 输入框区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// 内容输入框
                    TextField(
                      controller: contentController,
                      maxLines: null,
                      minLines: 5,
                      decoration: const InputDecoration(
                        hintText: "这一刻的想法...",
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),

                    const SizedBox(height: 20),

                    ///  图片展示及上传按钮 (修复后可展示多图)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ...imageList.map((url) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              url,
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                  width: 100, height: 100, color: Colors.grey[200], child: const Icon(Icons.image_not_supported)
                              ),
                            ),
                          );
                        }).toList(),

                        if (imageList.length < 9)
                          GestureDetector(
                            onTap: uploadImage,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEDEDED),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.add, size: 40, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    /// 话题选择
                    GestureDetector(
                      onTap: showTopicSelector,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.35,
                          minWidth: 80,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F2),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          topicName ?? "# 话题",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),

                    const Divider(),

                    /// 定位选择
                    ListTile(
                      leading: const Icon(Icons.location_on),
                      title: Text(
                        locationName ?? "你在哪里",
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        setState(() {
                          showLocationPanel = !showLocationPanel;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            /// 定位列表区域
            if (showLocationPanel)
              Container(
                height: MediaQuery.of(context).size.height * 0.5,
                child: Column(
                  children: [
                    /// 搜索附近位置
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        controller: locationSearchController,
                        decoration: InputDecoration(
                          hintText: "搜索附近位置",
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: const Color(0xfff2f2f2),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) => searchLocation(value),
                      ),
                    ),

                    /// 附近位置列表
                    Expanded(
                      child: ListView.builder(
                        itemCount: locationList.length,
                        itemBuilder: (context, index) {
                          var item = locationList[index];
                          return ListTile(
                            title: Text(item["name"], overflow: TextOverflow.ellipsis, maxLines: 1),
                            subtitle: Text("${item["distance"]} | ${item["address"]}", overflow: TextOverflow.ellipsis, maxLines: 1),
                            onTap: () {
                              setState(() {
                                locationName = item["name"];
                                showLocationPanel = false;
                                locationSearchController.clear();
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}