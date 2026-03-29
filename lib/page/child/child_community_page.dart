import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart' hide TextDirection; // 💡 隐藏 intl 里的 TextDirection，解决命名冲突
import '../../utils/api_client.dart'; // 💡 引入请求客户端
import 'post_detail_page.dart';

class ChildCommunityPage extends StatefulWidget {
  const ChildCommunityPage({super.key});

  @override
  State<ChildCommunityPage> createState() => _ChildCommunityPageState();
}

class _ChildCommunityPageState extends State<ChildCommunityPage> {
  List<Map<String, dynamic>> postList = [];
  final TextEditingController searchController = TextEditingController();
  bool isLoading = true;

  String? province;
  String? city;
  String? district;

  List<String> provinces = [];
  List<String> cities = [];
  List<String> districts = [];

  String openType = "";

  String currentUserId = ""; // 💡 用于判断帖子是不是自己发的
  String currentUserNickname = "";
  String currentUserAvatar = "";

  @override
  void initState() {
    super.initState();
    loadUserInfo();
    loadProvinceList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loadPostList(); // 每次进入页面刷新
  }

  // 💡 获取当前登录用户的信息
  loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // 假设你在登录成功时保存了 userId
      currentUserId = prefs.getString("userId") ?? "";
      currentUserNickname = prefs.getString("nickname") ?? "";
      currentUserAvatar = prefs.getString("avatarUrl") ?? "";
    });
  }

  // 省市县假数据 (用于筛选)
  loadProvinceList() {
    provinces = ["全部省份", "广东省", "北京市", "上海市", "浙江省", "江苏省"];
    setState(() {});
  }

  loadCityList(String province) {
    if (province == "广东省") cities = ["全部城市", "广州市", "深圳市"];
    else if (province == "北京市") cities = ["全部城市", "北京市"];
    else if (province == "上海市") cities = ["全部城市", "上海市"];
    else if (province == "浙江省") cities = ["全部城市", "杭州市"];
    else if (province == "江苏省") cities = ["全部城市", "南京市"];
    else cities = ["全部城市"];
    setState(() {});
  }

  loadDistrictList(String city) {
    if (city == "广州市") districts = ["全部区县", "番禺区", "天河区"];
    else if (city == "深圳市") districts = ["全部区县", "南山区", "福田区"];
    else if (city == "北京市") districts = ["全部区县", "海淀区", "朝阳区"];
    else if (city == "南京市") districts = ["全部区县", "玄武区"];
    else districts = ["全部区县"];
    setState(() {});
  }

  // ==========================================
  // 🌐 真实接口：获取帖子列表
  // ==========================================
  Future<void> loadPostList() async {
    setState(() => isLoading = true);

    try {
      // 构建动态查询参数
      List<String> queryParams = [];
      if (province != null && province != "全部省份") queryParams.add("province=$province");
      if (city != null && city != "全部城市") queryParams.add("city=$city");
      if (district != null && district != "全部区县") queryParams.add("district=$district");
      if (searchController.text.isNotEmpty) queryParams.add("keyword=${searchController.text}");

      String queryString = queryParams.isNotEmpty ? "?${queryParams.join('&')}" : "";

      var response = await ApiClient().get('/api/community/post/list$queryString');

      if (response != null) {
        List<dynamic> list = response is List ? response : (response['data'] ?? []);

        setState(() {
          postList = list.map((e) {
            Map<String, dynamic> post = Map<String, dynamic>.from(e);

            // 💡 解析后端逗号分隔的图片字符串
            String imageStr = post['images'] ?? "";
            post['imagesList'] = imageStr.isNotEmpty ? imageStr.split(',') : [];

            // 判断是否是自己发布的
            post['isMe'] = post['userId'].toString() == currentUserId;

            // 格式化时间 (防止空指针)
            if (post['createTime'] != null) {
              DateTime dt = DateTime.parse(post['createTime']).toLocal();
              post['time'] = DateFormat('yyyy-MM-dd HH:mm').format(dt);
            } else {
              post['time'] = "刚刚";
            }
            return post;
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("拉取社区帖子失败: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ==========================================
  // 🌐 真实接口：删除自己的帖子
  // ==========================================
  Future<void> deletePost(int index) async {
    var post = postList[index];
    int postId = post['postId'];

    // 乐观更新：先在 UI 上删掉
    setState(() => postList.removeAt(index));

    try {
      await ApiClient().delete('/api/community/post/$postId');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("删除成功")));
    } catch (e) {
      // 删除失败则恢复列表
      setState(() => postList.insert(index, post));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("删除失败，请重试")));
    }
  }

  // ==========================================
  // 🌐 真实接口：点赞 / 取消点赞
  // ==========================================
  Future<void> toggleLike(int index) async {
    var post = postList[index];
    int postId = post['postId'];
    bool currentLiked = post['isLikedByMe'] ?? false;
    int currentLikeCount = post['likeCount'] ?? 0;

    // 乐观更新 UI
    setState(() {
      post['isLikedByMe'] = !currentLiked;
      post['likeCount'] = currentLiked ? currentLikeCount - 1 : currentLikeCount + 1;
    });

    try {
      // 根据后端，使用 POST 传递 postId 参数
      await ApiClient().post('/api/community/post/like?postId=$postId');
    } catch (e) {
      // 失败则回滚 UI
      setState(() {
        post['isLikedByMe'] = currentLiked;
        post['likeCount'] = currentLikeCount;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("操作失败，请检查网络")));
    }
  }

  /// 展开列表组件
  Widget expandList() {
    List<String> data = [];
    if (openType == "province") data = provinces;
    if (openType == "city") data = cities;
    if (openType == "district") data = districts;

    if (openType == "") return const SizedBox();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: Column(
        children: data.map((e) {
          return ListTile(
            title: Text(e),
            onTap: () {
              setState(() {
                if (openType == "province") {
                  province = e == "全部省份" ? null : e;
                  city = null; district = null;
                  loadCityList(e);
                } else if (openType == "city") {
                  city = e == "全部城市" ? null : e;
                  district = null;
                  loadDistrictList(e);
                } else {
                  district = e == "全部区县" ? null : e;
                }
                openType = "";
                loadPostList(); // 筛选条件改变后，自动请求后端刷新
              });
            },
          );
        }).toList(),
      ),
    );
  }

  /// 筛选按钮组件
  Widget regionBtn({required String text, required String type}) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => openType = openType == type ? "" : type),
        child: Container(
          height: 46,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xffe8e7e7), borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
              const Icon(Icons.arrow_drop_down)
            ],
          ),
        ),
      ),
    );
  }

  /// 查看自己发布的帖子
  viewMyPosts() {
    Navigator.pushNamed(context, "/myPostPage").then((_) => loadPostList());
  }

  /// 图片网格组件
  Widget buildImageGrid(List images) {
    if (images.isEmpty) return const SizedBox();
    int imageCount = images.length;
    int displayCount = imageCount > 9 ? 9 : imageCount;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4, childAspectRatio: 1.0,
      ),
      itemCount: displayCount,
      itemBuilder: (context, index) {
        if (imageCount > 9 && index == 8) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.network(images[index], fit: BoxFit.cover),
              Container(
                color: Colors.black54,
                child: Center(child: Text("+${imageCount - 8}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
              ),
            ],
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(images[index], fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[200], child: const Icon(Icons.image_not_supported, color: Colors.grey))),
        );
      },
    );
  }

  /// 帖子卡片组件
  Widget postCard(Map<String, dynamic> post, int index) {
    bool isLikedByMe = post["isLikedByMe"] ?? false;
    int likeCount = post["likeCount"] ?? 0;
    List images = post["imagesList"] ?? []; // 使用解析后的数组
    bool isMe = post["isMe"] ?? false;

    // TODO: 后端目前没有连表查询头像，这里暂时随机头像，后续后端完善后替换
    String displayAvatarUrl = isMe && currentUserAvatar.isNotEmpty
        ? currentUserAvatar
        : "https://i.pravatar.cc/150?u=${post['userId']}";

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => PostDetailPage(post: post, postIndex: index, isFromMyPost: false)),
        ).then((_) => loadPostList());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(bottom: 10),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(12))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 头像 + 昵称 + 时间 + 我标签
            ListTile(
              leading: CircleAvatar(radius: 26, backgroundImage: NetworkImage(displayAvatarUrl)),
              title: Row(
                children: [
                  Text(
                    isMe ? (currentUserNickname.isNotEmpty ? currentUserNickname : "我") : (post["authorName"] ?? "社区用户"),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.orange),
                  ),
                  if (isMe)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                      child: const Text("我", style: TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                ],
              ),
              subtitle: Text(post["time"] ?? ""),
              trailing: isMe
                  ? PopupMenuButton(
                itemBuilder: (context) => [const PopupMenuItem(value: "delete", child: Text("删除"))],
                onSelected: (value) { if (value == "delete") deletePost(index); },
              )
                  : const Icon(Icons.expand_more),
            ),

            /// 正文
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ExpandableTextWidget(post["content"] ?? "", maxLines: 3),
            ),
            const SizedBox(height: 10),

            /// 图片区域
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: buildImageGrid(images),
            ),

            /// 定位
            if (post["location"] != null && post["location"].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(post["location"], style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),

            /// 评论 + 点赞区域
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Row(
                  children: [
                    const Icon(Icons.chat, size: 20),
                    const SizedBox(width: 6),
                    Text("${post["commentCount"] ?? 0}", style: const TextStyle(fontSize: 14)), // 目前还没评论功能，暂时显示 0
                  ],
                ),
                GestureDetector(
                  onTap: () => toggleLike(index), // 💡 触发真实点赞
                  child: Row(
                    children: [
                      Icon(Icons.thumb_up, color: isLikedByMe ? Colors.blue : Colors.grey, size: 20),
                      const SizedBox(width: 6),
                      Text("$likeCount", style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff7f8fa),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 20),

              /// 搜索栏
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(color: const Color(0xffe8e7e7), borderRadius: BorderRadius.circular(12)),
                        child: TextField(
                          controller: searchController,
                          textInputAction: TextInputAction.search, // 软键盘显示为“搜索”
                          onSubmitted: (value) => loadPostList(),  // 💡 用户按下回车搜索时，请求后端
                          decoration: const InputDecoration(
                            hintText: "搜索帖子内容",
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 12), // 修正对齐
                            suffixIcon: Icon(Icons.search, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff2d8cf0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          onPressed: () {
                            Navigator.pushNamed(context, "/createPostPage").then((_) => loadPostList());
                          },
                          child: const Text("发帖", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    )
                  ],
                ),
              ),

              const SizedBox(height: 10),

              /// 筛选栏
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    regionBtn(text: province ?? "全部省份", type: "province"),
                    regionBtn(text: city ?? "全部城市", type: "city"),
                    regionBtn(text: district ?? "全部区县", type: "district"),
                  ],
                ),
              ),

              const SizedBox(height: 6),

              /// 展开列表区域
              expandList(),
              const SizedBox(height: 10),

              /// 帖子列表
              Expanded(
                child: RefreshIndicator(
                  onRefresh: loadPostList, // 下拉刷新
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : postList.isEmpty
                      ? ListView(children: const [SizedBox(height: 200), Center(child: Text("暂无社区帖子，快来发一篇吧~", style: TextStyle(color: Colors.grey)))])
                      : ListView.builder(
                    itemCount: postList.length,
                    itemBuilder: (context, index) => postCard(postList[index], index),
                  ),
                ),
              ),
            ],
          ),

          /// 我的帖子按钮
          Positioned(
            bottom: 135,
            right: 16,
            child: GestureDetector(
              onTap: viewMyPosts,
              child: Container(
                width: 120, height: 48, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xff2d8cf0),
                  borderRadius: BorderRadius.circular(24), // 改为药丸形状更美观
                  boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
                ),
                child: const Text("我的帖子", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 文本展开组件保持不变
class ExpandableTextWidget extends StatefulWidget {
  final String text;
  final int maxLines;

  const ExpandableTextWidget(this.text, {super.key, this.maxLines = 3});

  @override
  State<ExpandableTextWidget> createState() => _ExpandableTextWidgetState();
}

class _ExpandableTextWidgetState extends State<ExpandableTextWidget> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, size) {
        final span = TextSpan(text: widget.text, style: const TextStyle(fontSize: 16));
        final painter = TextPainter(text: span, maxLines: widget.maxLines, textDirection: TextDirection.ltr)..layout(maxWidth: size.maxWidth);
        final overflow = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.text, maxLines: expanded ? null : widget.maxLines, overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
            if (overflow)
              GestureDetector(
                onTap: () => setState(() => expanded = !expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(expanded ? "收起" : "全文", style: const TextStyle(color: Colors.blue, fontSize: 14)),
                ),
              )
          ],
        );
      },
    );
  }
}