import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final TextEditingController commentController = TextEditingController();
  final FocusNode commentFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  String nickname = "";
  String avatarUrl = "";
  Map currentPost = {};
  List commentList = [];
  final Set<String> _likedCommentIds = <String>{};
  String _likedCommentStorageKey = "";

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    commentController.dispose();
    commentFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  loadData() async {
    final prefs = await SharedPreferences.getInstance();
    nickname = prefs.getString('nickname') ?? "用户";
    avatarUrl = prefs.getString('avatarUrl') ?? "";

    debugPrint('[PostDetail] loadData start postId=${widget.post["postId"]}, postIndex=${widget.postIndex}, nickname=$nickname');

    currentPost = Map.from(widget.post);
    _likedCommentStorageKey = 'liked_comment_ids_${currentPost["postId"] ?? widget.postIndex}';
    final savedLikedIds = prefs.getStringList(_likedCommentStorageKey) ?? <String>[];
    _likedCommentIds
      ..clear()
      ..addAll(savedLikedIds);

    await _refreshPostDetail();

    debugPrint('[PostDetail] after refresh commentCount=${(currentPost["comments"] as List?)?.length ?? 0}, likedIds=${_likedCommentIds.length}');

    final dynamic rawImages = currentPost["imagesList"] ?? currentPost["images"];
    if (rawImages is String) {
      currentPost["images"] = rawImages.isNotEmpty ? rawImages.split(',') : [];
    } else if (rawImages is List) {
      currentPost["images"] = rawImages;
    } else {
      currentPost["images"] = [];
    }

    bool isCurrentUserPost = (nickname == currentPost["nickname"]);
    currentPost["isMe"] = isCurrentUserPost;

    setState(() {});
  }

  Future<void> _refreshPostDetail() async {
    try {
      debugPrint('[PostDetail] refresh request -> GET /api/community/post/detail?postId=${currentPost["postId"]}');
      final response = await ApiClient().get('/api/community/post/detail?postId=${currentPost["postId"]}');
      debugPrint('[PostDetail] refresh response type=${response.runtimeType} value=$response');
      if (response == null || !mounted) return;

      final Map<String, dynamic> freshPost = response is Map
          ? Map<String, dynamic>.from(response['data'] ?? response)
          : Map<String, dynamic>.from(response);

      final dynamic freshCommentsRaw = freshPost['comments'] ?? freshPost['commentList'] ?? [];
      final List freshComments = freshCommentsRaw is List ? List.from(freshCommentsRaw) : [];

      freshPost['images'] = freshPost['images'] ?? freshPost['imagesList'] ?? [];
      freshPost['comments'] = freshComments;
      freshPost['isMe'] = (nickname == (freshPost['nickname'] ?? freshPost['authorName'] ?? ''));

      _likedCommentIds.clear();
      final List<Map<String, dynamic>> mergedComments = [];
      for (final comment in freshComments) {
        final Map<String, dynamic> c = Map<String, dynamic>.from(comment);
        c['nickname'] ??= '匿名用户';
        c['avatarUrl'] = c['avatarUrl'] ?? c['avatar'] ?? '';
        c['likeCount'] = c['likeCount'] ?? 0;
        c['isAuthor'] = c['isAuthor'] ?? false;

        final String commentId = c['id']?.toString() ?? '';
        final bool isBackendLiked = c['liked'] == true;
        c['liked'] = isBackendLiked;

        if (c['liked'] && commentId.isNotEmpty) {
          _likedCommentIds.add(commentId);
        }
        mergedComments.add(c);
      }

      if (mounted) {
        setState(() {
          currentPost = freshPost;
          commentList = mergedComments;
        });
        debugPrint('[PostDetail] refresh after like commentCount=${commentList.length}, likedIds=${_likedCommentIds.length}, postLiked=${currentPost["isLikedByMe"]}');
      }

      debugPrint('[PostDetail] refresh parsed comments=${freshComments.length}, likedIds=${_likedCommentIds.length}');
      await _persistLikedCommentIds();
    } catch (e) {
      debugPrint('刷新帖子详情失败: $e');
    }
  }

  likeComment(int commentIndex) async {
    var comment = commentList[commentIndex];
    final String commentId = comment["id"]?.toString() ?? "";
    if (commentId.isEmpty) {
      debugPrint('[PostDetail][likeComment] empty commentId at index=$commentIndex');
      return;
    }

    // 🌟 此时可以直接放心地读取数据源状态
    final bool isCurrentlyLiked = comment["liked"] == true;
    debugPrint('[PostDetail][likeComment] tap index=$commentIndex id=$commentId currentlyLiked=$isCurrentlyLiked likeCount=${comment["likeCount"]} commentLikedIds=${_likedCommentIds.contains(commentId)}');

    setState(() {
      comment["liked"] = !isCurrentlyLiked;
      if (comment["liked"]) {
        comment["likeCount"] = (comment["likeCount"] ?? 0) + 1;
        _likedCommentIds.add(commentId);
      } else {
        comment["likeCount"] = math.max(0, (comment["likeCount"] ?? 1) - 1);
        _likedCommentIds.remove(commentId);
      }
    });
    debugPrint('[PostDetail][likeComment] optimistic liked=${comment["liked"]} likeCount=${comment["likeCount"]}');
    _persistLikedCommentIds();

    try {
      final res = await ApiClient().post('/api/community/comment/like?commentId=$commentId');
      debugPrint('[PostDetail][likeComment] api response=$res');
      await _refreshPostDetail();
    } catch (e) {
      // 🌟【修复核心 3】：完善网络失败时的 UI 回滚逻辑
      if (mounted) {
        setState(() {
          comment["liked"] = isCurrentlyLiked;
          if (isCurrentlyLiked) {
            _likedCommentIds.add(commentId);
            comment["likeCount"] = (comment["likeCount"] ?? 0) + 1;
          } else {
            _likedCommentIds.remove(commentId);
            comment["likeCount"] = math.max(0, (comment["likeCount"] ?? 1) - 1);
          }
        });
        debugPrint('[PostDetail][likeComment] rollback liked=$isCurrentlyLiked likeCount=${comment["likeCount"]}');
        _persistLikedCommentIds();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("操作失败: $e")));
      }
      debugPrint("评论点赞操作失败: $e");
    }
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

        // 🌟【修复核心 4】：UI 渲染只依赖 c["liked"] 一处，干脆利落
        final bool isLiked = c["liked"] == true;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey.shade200,
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
                        Text(c["nickname"], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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

                        if (c["nickname"] == nickname)
                          GestureDetector(
                            onTap: () {
                              _showDeleteCommentDialog(index, c["id"].toString());
                            },
                            child: const Padding(
                              padding: EdgeInsets.only(right: 15.0),
                              child: Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                            ),
                          ),

                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            final String commentId = c["id"]?.toString() ?? "";
                            debugPrint('[PostDetail][likeButton] tapped index=$index id=$commentId uiLiked=$isLiked backendLiked=${c["liked"] == true} likeCount=${c["likeCount"]}');
                            likeComment(index);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Row(children: [
                              Icon(isLiked ? Icons.favorite : Icons.favorite_border, size: 18, color: isLiked ? Colors.red : Colors.grey),
                              const SizedBox(width: 4),
                              Text("${c["likeCount"] ?? 0}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ]),
                          ),
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

  Future<void> _persistLikedCommentIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_likedCommentStorageKey, _likedCommentIds.toList());
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

    debugPrint('[PostDetail][addComment] tap content=${commentController.text.trim()} postId=${currentPost["postId"]}');

    try {
      var response = await ApiClient().post('/api/community/post/comment', data: {
        "postId": currentPost["postId"],
        "content": commentController.text.trim()
      });
      debugPrint('[PostDetail][addComment] api response=$response');

      // 解析后端返回的真实评论 ID
      String realCommentId = "";
      if (response != null) {
        if (response is Map && response['data'] != null) {
          realCommentId = response['data'].toString();
        } else {
          // 无论拦截器直接丢出来的是 int 还是 String，直接转字符串
          realCommentId = response.toString();
        }
      }
// 只有真正的极端情况才用时间戳防崩溃
      if (realCommentId.isEmpty || realCommentId == "null") {
        realCommentId = DateTime.now().millisecondsSinceEpoch.toString();
        debugPrint("！！！评论id出错，兜底设置为时间戳！！！"
                   "！！！评论id出错，兜底设置为时间戳！！！"
                    "！！！评论id出错，兜底设置为时间戳！！！");
      }

      bool isAuthor = (nickname == currentPost["nickname"] || nickname == currentPost["authorName"]);

      Map newComment = {
        "id": realCommentId, // 评论ID
        "nickname": nickname, // 用户昵称
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
      debugPrint('[PostDetail][addComment] optimistic appended localCommentId=$realCommentId total=${commentList.length}');
      await _refreshPostDetail();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });

      commentController.clear();
      FocusScope.of(context).unfocus();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("评论失败: $e")));
    }
  }



// 🌟 删除评论的网络请求
  Future<void> _deleteComment(int index, String commentId) async {
    try {
      await ApiClient().post('/api/community/comment/delete', data: {
        "id": commentId,
      });

      // 只要没有进入 catch，就说明请求成功了！直接刷新 UI，不要判断 response != null
      if (mounted) {
        setState(() {
          commentList.removeAt(index); // 从本地列表中移除该条评论
        });
        await _refreshPostDetail();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("评论已删除"),
              duration: Duration(milliseconds: 500), // 设置为 1 秒后自动消失
            )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("删除失败: $e")));
      }
    }
  }


  // 🌟 删除评论确认弹窗
  void _showDeleteCommentDialog(int index, String commentId) {
    // 💡 第一道防线：在弹起确认框的瞬间，强制输入框失焦
    commentFocusNode.unfocus();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("删除评论"),
        content: const Text("确定要删除这条评论吗？"),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(context); // 先关闭弹窗
                // 💡 第二道防线：关闭弹窗后，再次确保输入框被死死按住
                commentFocusNode.unfocus();
              },
              child: const Text("取消")
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // 先关闭弹窗
              // 💡 第二道防线：关闭弹窗后，再次确保输入框被死死按住
              commentFocusNode.unfocus();

              _deleteComment(index, commentId); // 再执行删除
            },
            child: const Text("删除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }


  likePost() async {
    final bool currentLiked = currentPost["liked"] == true || currentPost["isLikedByMe"] == true;
    final int currentLikeCount = (currentPost["likeCount"] ?? 0) as int;
    debugPrint('[PostDetail][likePost] tap postId=${currentPost["postId"]} currentLiked=$currentLiked likeCount=$currentLikeCount');

    setState(() {
      final bool nextLiked = !currentLiked;
      currentPost["liked"] = nextLiked;
      currentPost["isLikedByMe"] = nextLiked;
      currentPost["likeCount"] = nextLiked ? currentLikeCount + 1 : math.max(0, currentLikeCount - 1);
    });

    try {
      final res = await ApiClient().post('/api/community/post/like?postId=${currentPost["postId"]}');
      debugPrint('[PostDetail][likePost] api response=$res');
      await _refreshPostDetail();
    } catch (e) {
      debugPrint("帖子点赞失败: $e");
      if (mounted) {
        setState(() {
          currentPost["liked"] = currentLiked;
          currentPost["isLikedByMe"] = currentLiked;
          currentPost["likeCount"] = currentLikeCount;
        });
      }
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
    final dynamic rawImages = currentPost["images"] ?? currentPost["imagesList"] ?? [];
    final List images = rawImages is List
        ? rawImages
        : (rawImages is String && rawImages.isNotEmpty)
            ? rawImages.split(',')
            : <String>[];

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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  debugPrint('[PostDetail][commentIcon] tapped, currentFocus=${commentFocusNode.hasFocus}');
                  FocusScope.of(context).unfocus();
                  FocusManager.instance.primaryFocus?.unfocus();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      FocusScope.of(context).requestFocus(commentFocusNode);
                      debugPrint('[PostDetail][commentIcon] afterRequestFocus hasFocus=${commentFocusNode.hasFocus}');
                    }
                  });
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [Icon(Icons.chat_bubble_outline, color: Colors.grey), SizedBox(width: 6), Text("评论", style: TextStyle(color: Colors.grey))]),
                ),
              ),
              GestureDetector(
                onTap: likePost,
                child: Row(children: [
                  Icon((currentPost["liked"] == true || currentPost["isLikedByMe"] == true) ? Icons.thumb_up : Icons.thumb_up_alt_outlined, color: (currentPost["liked"] == true || currentPost["isLikedByMe"] == true) ? Colors.blue : Colors.grey),
                  const SizedBox(width: 6),
                  Text("${currentPost["likeCount"] ?? 0}", style: TextStyle(color: (currentPost["liked"] == true || currentPost["isLikedByMe"] == true) ? Colors.blue : Colors.grey)),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildInputBar() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: commentController,
              focusNode: commentFocusNode,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => addComment(),
              decoration: const InputDecoration(hintText: "写评论...", border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.blue),
            onPressed: () {
              debugPrint('[PostDetail][commentButton] clicked text=${commentController.text.trim()} focus=${commentFocusNode.hasFocus}');
              addComment();
            },
          ),
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
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                FocusScope.of(context).unfocus();
              },
              child: SingleChildScrollView(
                controller: _scrollController,
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
          ),
          buildInputBar(),
        ],
      ),
    );
  }
}