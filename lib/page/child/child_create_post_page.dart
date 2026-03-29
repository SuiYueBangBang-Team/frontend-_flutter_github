import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});

  @override
  State<CreatePostPage> createState() =>
      _CreatePostPageState();
}

class _CreatePostPageState
    extends State<CreatePostPage> {

  final TextEditingController
  contentController =
  TextEditingController();

  final TextEditingController
  locationSearchController =
  TextEditingController();

  String? locationName;

  String? topicName;

  String cityName = "定位中...";

  bool showLocationPanel = false;

  List<Map> locationList = [];

  List<Map> originLocationList = [];

  List<String> topicList = [];

  List<String> imageList = [];

  @override
  void initState() {

    super.initState();

    loadCurrentLocation();

    loadRecommendLocation();

    loadTopicList();

    loadCurrentCity();

  }


  /// 当前定位
  loadCurrentLocation() async {

    setState(() {

      locationName =
      "广州应用科技学院（肇庆校区）";

    });

  }


  /// 当前城市


  loadCurrentCity() async {

    setState(() {

      cityName = "肇庆市";

    });

  }


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

        locationList =
            originLocationList;

      });

      return;

    }

    List<Map> nearbyList =
    originLocationList.where((item) {

      return item["name"]
          .contains(keyword);

    }).toList();

    setState(() {

      locationList =
          nearbyList;

    });

  }


  /// 话题列表


  loadTopicList() async {

    setState(() {

      topicList = [

        "育儿经验",

        "健康守护",

        "家庭关系",

        "长辈陪伴"

      ];

    });

  }


  /// 上传图片接口预留
  uploadImage() async {
    /// ===== 后端上传图片接口预留 =====
    /*
    Http.upload(
      "/upload/image",
      files: {
        "file": imageFile
      },
      onSuccess: (response) {
        String imageUrl = response["url"];
        setState(() {
          imageList.add(imageUrl);
        });
      }
    );
    */
  }

  /// 发布帖子核心函数（完整修复版）
  publishPost() async {
    if (contentController.text.isEmpty) return;

    if (locationName == null) {

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("请选择定位后再发布")),
      );
      return;
    }

    final prefs =
    await SharedPreferences.getInstance();

    /// 获取用户信息
    String nickname =
        prefs.getString("nickname") ?? "用户";

    String avatarUrl =
        prefs.getString("avatarUrl") ?? "";


    /// 创建帖子对象
    Map post = {

      "nickname": nickname,

      "avatarUrl": avatarUrl,

      "content": contentController.text,

      "images": imageList,

      "location": locationName,

      "time": DateTime.now().toString(),

      "comments": [],

      "likeCount": 0,

      "liked": false,

    };


    /// 写入社区帖子列表
    String? communityData =
    prefs.getString("communityPostList");

    List communityList =
    communityData == null
        ? []
        : jsonDecode(communityData);

    communityList.insert(0, post);

    await prefs.setString(

      "communityPostList",

      jsonEncode(communityList),

    );


    /// 写入我的帖子列表
    String? myData =
    prefs.getString("postList");

    List myList =
    myData == null
        ? []
        : jsonDecode(myData);

    myList.insert(0, post);

    await prefs.setString(

      "postList",

      jsonEncode(myList),

    );


    /// 后端接口预留
    /*
    Http.post(
    "/community/post/create",
    params:{
    "content":contentController.text,
    "images":imageList,
    "location":locationName
    }
    );
    */


    /// 返回社区页面
    Navigator.pop(context);

  }


  /// 话题选择器
  showTopicSelector() {

    showModalBottomSheet(

      context: context,

      builder: (context) {

        return ListView(

          children:

          topicList.map((topic) {

            return ListTile(

              title: Text(topic),

              onTap: () {

                setState(() {

                  topicName = topic;

                });

                Navigator.pop(context);

              },

            );

          }).toList(),

        );

      },

    );

  }


  /// 页面UI
  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: Colors.white,

      body: SafeArea(

        child: Column(

          children: [

            /// 顶部栏
            Padding(

              padding:
              const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10),

              child: Row(

                mainAxisAlignment:
                MainAxisAlignment.spaceBetween,

                children: [

                  GestureDetector(

                    onTap:
                        () =>
                        Navigator.pop(context),

                    child: const Text(

                      "取消",

                      style: TextStyle(

                        fontSize: 18,

                        fontWeight:
                        FontWeight.bold,

                      ),

                    ),

                  ),

                  GestureDetector(

                    onTap: publishPost,

                    child: Container(

                      padding:
                      const EdgeInsets.symmetric(

                          horizontal: 18,

                          vertical: 6),

                      decoration:
                      BoxDecoration(

                        color:
                        contentController
                            .text
                            .isEmpty

                            ? const Color(
                            0xFFE5E5E5)

                            : const Color(
                            0xFF4A7BFF),

                        borderRadius:
                        BorderRadius.circular(
                            20),

                      ),

                      child: const Text(

                        "发表",

                        style: TextStyle(
                            color:
                            Colors.white),

                      ),

                    ),

                  ),

                ],

              ),

            ),


            /// 输入框区域
            Padding(

              padding:
              const EdgeInsets.symmetric(
                  horizontal: 16),

              child: Column(

                children: [

                  TextField(

                    controller:
                    contentController,

                    maxLines: 5,

                    decoration:
                    const InputDecoration(

                      hintText:
                      "这一刻的想法...",

                      border:
                      InputBorder.none,

                    ),

                    onChanged:
                        (_) => setState(() {}),

                  ),

                  const SizedBox(height: 20),


                  /// 图片上传按钮
                  Align(

                    alignment: Alignment.centerLeft,

                    child: GestureDetector(

                      onTap: uploadImage,

                      child: Container(

                        width: 130,
                        height: 130,

                        decoration: BoxDecoration(

                          color: const Color(0xFFEDEDED),

                          borderRadius:
                          BorderRadius.circular(8),

                        ),

                        child: const Icon(
                          Icons.add,
                          size: 40,
                        ),

                      ),

                    ),

                  ),

                  const SizedBox(height: 20),


                  /// 话题选择
                  Align(

                    alignment:
                    Alignment.centerLeft,

                    child: GestureDetector(

                      onTap: showTopicSelector,

                      child: Container(

                        width:
                        MediaQuery.of(context)
                            .size
                            .width *
                            0.25,

                        padding:
                        const EdgeInsets.symmetric(
                            vertical: 8),

                        alignment:
                        Alignment.center,

                        decoration:
                        BoxDecoration(

                          color:
                          const Color(
                              0xFFF2F2F2),

                          borderRadius:
                          BorderRadius.circular(
                              18),

                        ),

                        child: Text(

                          topicName ??
                              "# 话题",

                          style:
                          const TextStyle(

                            fontSize: 16,

                            fontWeight:
                            FontWeight.w600,

                          ),

                        ),

                      ),

                    ),

                  ),

                  const Divider(),


                  /// 定位选择
                  ListTile(

                    leading:
                    const Icon(Icons.location_on),

                    title: Text(

                        locationName ??
                            "你在哪里"),

                    trailing:
                    const Icon(
                        Icons.chevron_right),

                    onTap: () {

                      setState(() {

                        showLocationPanel =
                        !showLocationPanel;

                      });

                    },

                  ),

                ],

              ),

            ),

            /// 定位列表区域
            if (showLocationPanel)
              Expanded(
                child: Column(
                  children: [

                    /// 搜索附近位置输入框
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8),
                      child: TextField(
                        controller: locationSearchController,
                        decoration: InputDecoration(
                          hintText: "搜索附近位置",
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: const Color(0xfff2f2f2),
                          border: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) {

                          /// 只搜索附近列表
                          searchLocation(value);

                          /// 后端接口预留
                          /*
                          Http.get(
                          "/location/searchNearby",
                          params:{
                          keyword:value,
                          city:cityName
                          }
                          );
                          */
                        },
                      ),
                    ),

                    /// 附近位置列表
                    Expanded(
                      child: ListView.builder(
                        itemCount: locationList.length,
                        itemBuilder: (context, index) {

                          var item = locationList[index];

                          return ListTile(
                            title: Text(item["name"]),
                            subtitle: Text(
                                "${item["distance"]} | ${item["address"]}"),
                            onTap: () {

                              setState(() {

                                locationName =
                                item["name"];

                                showLocationPanel =
                                false;

                              });

                            },
                          );

                        },
                      ),
                    )

                  ],
                ),
              )
          ],

        ),

      ),

    );

  }

}