import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../utils/api_client.dart';

class PostDetailPage extends StatefulWidget {
  final Map post;
  final int postIndex;
  final bool isFromMyPost;

  const PostDetailPage({
    super.key,
    required this.post,
    required this.postIndex,
    required this.isFromMyPost,
  });

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  TextEditingController commentController = TextEditingController();
  FocusNode commentFocusNode = FocusNode();
  String nickname = "";
  String avatarUrl = "";
  Map currentPost = {};
  List commentList = [];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    commentController.dispose();
    commentFocusNode.dispose();
    super.dispose();
  }

  loadData() async {
    final prefs = await SharedPreferences.getInstance();
    nickname = prefs.getString('nickname') ?? "用户";
    avatarUrl = prefs.getString('avatarUrl') ?? "";

    currentPost = Map.from(widget.post);

    var rawImages = currentPost["imagesList"] ?? currentPost["images"];
    if (rawImages is String) {
      currentPost["images"] = rawImages.isNotEmpty ? rawImages.split(',') : [];
    } else if (rawImages is List) {
      currentPost["images"] = rawImages;
    } else {
      currentPost["images"] = [];
    }

    currentPost["comments"] = List.from(currentPost["comments"] ?? []);
    commentList = currentPost["comments"];

    bool isCurrentUserPost = (nickname == currentPost["nickname"]);
    currentPost["isMe"] = isCurrentUserPost;

    for (var comment in commentList) {
      comment["liked"] ??= false;
      comment["likeCount"] ??= 0;
      comment["time"] ??= "";
      comment["isAuthor"] = (comment["name"] == currentPost["nickname"]);
    }

    setState(() {});
  }

  String _formatTime(DateTime time) {
    return "${time.month}-${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}";
  }

  String _getCommentTime(String timeStr) {
    if (timeStr.isEmpty) return "";
    if (timeStr.contains("-") && timeStr.contains(":")) {
      return timeStr;
    }
    try {
      DateTime time = DateTime.parse(timeStr);
      return _formatTime(time);
    } catch (e) {
      return timeStr;
    }
  }

  addComment() async {
    if (commentController.text.trim().isEmpty) return;

    try {
      await ApiClient().post('/api/community/post/comment', data: {
        "postId": currentPost["postId"],
        "content": commentController.text.trim()
      });

      bool isAuthor = (nickname == currentPost["nickname"] || nickname == currentPost["authorName"]);
      Map newComment = {
        "id": DateTime.now().millisecondsSinceEpoch.toString(),
        "name": nickname,
        "avatarUrl": avatarUrl,
        "content": commentController.text.trim(),
        "time": _formatTime(DateTime.now()),
        "likeCount": 0,
        "liked": false,
        "isAuthor": isAuthor,
      };

      setState(() {
        commentList.add(newComment);
        currentPost["comments"] = commentList;
      });

      commentController.clear();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("评论成功")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("评论失败: $e")));
    }
  }

  likePost() async {
    setState(() {
      currentPost["liked"] = !(currentPost["liked"] ?? false);
      if (currentPost["liked"]) {
        currentPost["likeCount"] = (currentPost["likeCount"] ?? 0) + 1;
      } else {
        currentPost["likeCount"] = (currentPost["likeCount"] ?? 0) - 1;
      }
    });

    try {
      await ApiClient().post('/api/community/post/like?postId=${currentPost["postId"]}');
    } catch (e) {
      debugPrint("帖子点赞失败");
    }
  }

  likeComment(int commentIndex) async {
    var comment = commentList[commentIndex];
    setState(() {
      comment["liked"] = !(comment["liked"] ?? false);
      if (comment["liked"]) {
        comment["likeCount"] = (comment["likeCount"] ?? 0) + 1;
      } else {
        comment["likeCount"] = (comment["likeCount"] ?? 0) - 1;
      }
    });

    try {
      await ApiClient().post('/api/community/comment/like?commentId=${comment["id"]}');
    } catch (e) {
      debugPrint("评论点赞失败");
    }
  }

  Widget buildImageGrid(List images) {
    if (images.isEmpty) return const SizedBox();

    int imageCount = images.length;
    int displayCount = imageCount > 9 ? 9 : imageCount;
    bool hasMore = imageCount > 9;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4, childAspectRatio: 1.0,
      ),
      itemCount: displayCount,
      itemBuilder: (context, index) {
        if (hasMore && index == 8) {
          return GestureDetector(
            onTap: () {},
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(images[index], fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey.shade300)),
                Container(color: Colors.black54, child: Center(child: Text("+${imageCount - 8}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)))),
              ],
            ),
          );
        }
        return GestureDetector(
          onTap: () {},
          child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(images[index], fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey.shade300))),
        );
      },
    );
  }

  Widget buildPostHeader() {
    List images = currentPost["images"] ?? [];

    bool isMyPost = (widget.isFromMyPost || currentPost["isMe"] == true);
    String displayAvatarUrl = "";
    String displayNickname = "";

    if (isMyPost) {
      displayAvatarUrl = avatarUrl;
      displayNickname = nickname.isNotEmpty ? nickname : "我";
    } else {
      displayAvatarUrl = currentPost["avatarUrl"] ?? "";
      displayNickname = currentPost["nickname"] ?? currentPost["authorName"] ?? "用户";
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.grey.shade200,
                //  完全废弃本地图片兜底
                backgroundImage: displayAvatarUrl.isNotEmpty ? NetworkImage(displayAvatarUrl) : null,
                child: displayAvatarUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey, size: 30) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayNickname, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(currentPost["time"] ?? "", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              if (currentPost["location"] != null && currentPost["location"].toString().isNotEmpty)
                Row(children: [const Icon(Icons.location_on, size: 14, color: Colors.grey), const SizedBox(width: 4), Text(currentPost["location"], style: const TextStyle(color: Colors.grey, fontSize: 12))]),
            ],
          ),
          const SizedBox(height: 12),
          Text(currentPost["content"] ?? "", style: const TextStyle(fontSize: 16)),
          if (images.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: buildImageGrid(images)),
          const SizedBox(height: 12),
          Divider(color: Colors.grey.shade300, thickness: 0.5),
          Row(
            children: [
              Text("${commentList.length} 评论", style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(width: 24),
              Text("${currentPost["likeCount"] ?? 0} 赞", style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.grey.shade300, thickness: 0.5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              GestureDetector(onTap: () => commentFocusNode.requestFocus(), child: const Row(children: [Icon(Icons.chat_bubble_outline, color: Colors.grey), SizedBox(width: 6), Text("评论", style: TextStyle(color: Colors.grey))])),
              GestureDetector(
                onTap: likePost,
                child: Row(children: [
                  Icon((currentPost["liked"] ?? false) ? Icons.thumb_up : Icons.thumb_up_alt_outlined, color: (currentPost["liked"] ?? false) ? Colors.blue : Colors.grey),
                  const SizedBox(width: 6),
                  Text("${currentPost["likeCount"] ?? 0}", style: TextStyle(color: (currentPost["liked"] ?? false) ? Colors.blue : Colors.grey)),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildCommentList() {
    if (commentList.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text("暂无评论，快来抢沙发吧～", style: TextStyle(color: Colors.grey))));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: commentList.length,
      itemBuilder: (context, index) {
        var c = commentList[index];
        String commentAvatarUrl = c["avatarUrl"] ?? "";

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey.shade200,
                //  完全废弃本地图片兜底
                backgroundImage: commentAvatarUrl.isNotEmpty ? NetworkImage(commentAvatarUrl) : null,
                child: commentAvatarUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey, size: 24) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(c["name"], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(width: 6),
                        if (c["isAuthor"] == true)
                          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)), child: const Text("作者", style: TextStyle(color: Colors.white, fontSize: 10))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(c["content"], style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(_getCommentTime(c["time"]), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => likeComment(index),
                          child: Row(children: [
                            Icon((c["liked"] == true) ? Icons.favorite : Icons.favorite_border, size: 14, color: (c["liked"] == true) ? Colors.red : Colors.grey),
                            const SizedBox(width: 4),
                            Text("${c["likeCount"] ?? 0}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildInputBar() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(child: TextField(controller: commentController, focusNode: commentFocusNode, decoration: const InputDecoration(hintText: "写评论...", border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)))),
          IconButton(icon: const Icon(Icons.send, color: Colors.blue), onPressed: addComment),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(title: const Text("帖子详情"), elevation: 0),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  buildPostHeader(),
                  const SizedBox(height: 8),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Text("评论", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(width: 8),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)), child: Text("${commentList.length}", style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
                      ],
                    ),
                  ),
                  buildCommentList(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          buildInputBar(),
        ],
      ),
    );
  }
}