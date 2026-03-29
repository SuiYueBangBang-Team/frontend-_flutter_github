// child_my_post_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'post_detail_page.dart';

class MyPostPage extends StatefulWidget {
  const MyPostPage({super.key});

  @override
  State<MyPostPage> createState() => _MyPostPageState();
}

class _MyPostPageState extends State<MyPostPage> {
  String nickname = "";
  String avatarUrl = "";
  List postList = [];

  deletePost(index) async {
    final prefs = await SharedPreferences.getInstance();
    var post = postList[index];
    postList.removeAt(index);
    await prefs.setString("postList", jsonEncode(postList));

    String? communityData = prefs.getString("communityPostList");
    if (communityData != null) {
      List communityList = jsonDecode(communityData);
      communityList.removeWhere((item) => item["time"] == post["time"]);
      await prefs.setString("communityPostList", jsonEncode(communityList));
    }
    /// ===== 后端删除帖子接口预留 =====
    /*
    Http.delete(
      "/community/post/${post["id"]}",
      params: {
        postId: post["id"]
      }
    );
    */
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    loadData();
  }

  loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      nickname = prefs.getString("nickname") ?? "";
      avatarUrl = prefs.getString("avatarUrl") ?? "";
    });

    String? data = prefs.getString("postList");
    if (data != null) {
      postList = jsonDecode(data);
      for (var post in postList) {
        post["liked"] ??= false;
        post["likeCount"] ??= 0;
        post["comments"] ??= [];
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f6f7),
      appBar: AppBar(title: const Text("我的帖子")),
      body: postList.isEmpty
          ? const Center(
        child: Text(
          "暂无帖子，去社区发布吧～",
          style: TextStyle(color: Colors.grey),
        ),
      )
          : ListView.builder(
        itemCount: postList.length,
        itemBuilder: (context, index) {
          var post = postList[index];
          return postCard(post, index);
        },
      ),
    );
  }

  /// 图片网格组件
  Widget buildImageGrid(List images) {
    if (images.isEmpty) return const SizedBox();

    int imageCount = images.length;
    int displayCount = imageCount > 9 ? 9 : imageCount;
    bool hasMore = imageCount > 9;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1.0,
      ),
      itemCount: displayCount,
      itemBuilder: (context, index) {
        if (hasMore && index == 8) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                images[index],
                fit: BoxFit.cover,
              ),
              Container(
                color: Colors.black54,
                child: Center(
                  child: Text(
                    "+${imageCount - 8}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            images[index],
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }

  Widget postCard(post, index) {
    bool liked = post["liked"] ?? false;
    int likeCount = post["likeCount"] ?? 0;
    List images = post["images"] ?? [];

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailPage(
              post: post,
              postIndex: index,
              isFromMyPost: true,
            ),
          ),
        ).then((_) {
          loadData();
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(bottom: 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: CircleAvatar(
                radius: 26,
                backgroundImage: avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : const AssetImage("assets/images/avatar_ball.png") as ImageProvider,
              ),
              title: Text(
                nickname.isNotEmpty ? nickname : "我",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.orange,
                ),
              ),
              subtitle: Text(post["time"] ?? "昨天 15:20"),
              trailing: PopupMenuButton(
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: "delete",
                    child: Text("删除"),
                  )
                ],
                onSelected: (value) {
                  if (value == "delete") {
                    deletePost(index);
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ExpandableTextWidget(
                post["content"] ?? "",
                maxLines: 3,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: buildImageGrid(images),
            ),
            if (post["location"] != null && post["location"].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      post["location"],
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Row(
                  children: [
                    const Icon(Icons.chat, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      "${post["comments"]?.length ?? 0}",
                      style: const TextStyle(fontSize: 14),
                    )
                  ],
                ),
                StatefulBuilder(
                  builder: (context, setState) {
                    return GestureDetector(
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        setState(() {
                          liked = !liked;
                          if (liked) {
                            likeCount++;
                          } else {
                            likeCount--;
                          }
                          post["liked"] = liked;
                          post["likeCount"] = likeCount;
                        });
                        await prefs.setString("postList", jsonEncode(postList));
                      },
                      child: Row(
                        children: [
                          Icon(
                            Icons.thumb_up,
                            color: liked ? Colors.blue : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "$likeCount",
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
        final span = TextSpan(
          text: widget.text,
          style: const TextStyle(fontSize: 16),
        );
        final painter = TextPainter(
          text: span,
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.maxWidth);
        final overflow = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: expanded ? null : widget.maxLines,
              overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
            if (overflow)
              GestureDetector(
                onTap: () {
                  setState(() {
                    expanded = !expanded;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    expanded ? "收起" : "全文",
                    style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
          ],
        );
      },
    );
  }
}