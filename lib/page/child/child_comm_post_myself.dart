import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/api_client.dart';
import 'child_comm_post_detail.dart';

class MyPostPage extends StatefulWidget {
  const MyPostPage({super.key});

  @override
  State<MyPostPage> createState() => _MyPostPageState();
}

class _MyPostPageState extends State<MyPostPage> {
  String nickname = "";
  String avatarUrl = "";
  List<Map<String, dynamic>> postList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  loadData() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    nickname = prefs.getString("nickname") ?? "";
    avatarUrl = prefs.getString("avatarUrl") ?? "";

    try {
      var response = await ApiClient().get('/api/community/post/myList');
      if (response != null) {
        List<dynamic> list = response is List ? response : (response['data'] ?? []);

        setState(() {
          postList = list.map((e) {
            Map<String, dynamic> post = Map<String, dynamic>.from(e);

            var rawImages = post['images'];
            if (rawImages is String) {
              post['images'] = rawImages.isNotEmpty ? rawImages.split(',') : [];
            } else if (rawImages == null) {
              post['images'] = [];
            }

            if (post['createTime'] != null) {
              DateTime dt = DateTime.parse(post['createTime']).toLocal();
              post['time'] = "${dt.month}-${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
            } else {
              post['time'] = "刚刚";
            }

            post["liked"] = false;
            post["likeCount"] = post["likeCount"] ?? 0;
            post["comments"] = [];
            return post;
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("拉取我的帖子失败: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  deletePost(int index) async {
    var post = postList[index];
    int postId = post['postId'];

    setState(() => postList.removeAt(index));

    try {
      await ApiClient().delete('/api/community/post/$postId');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("删除成功")));
    } catch (e) {
      setState(() => postList.insert(index, post));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("删除失败，请检查网络")));
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f6f7),
      appBar: AppBar(title: const Text("我的帖子")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : postList.isEmpty
          ? const Center(child: Text("暂无帖子，去社区发布吧～", style: TextStyle(color: Colors.grey)))
          : ListView.builder(
        itemCount: postList.length,
        itemBuilder: (context, index) => postCard(postList[index], index),
      ),
    );
  }

  Widget buildImageGrid(List images) {
    if (images.isEmpty) return const SizedBox();
    int imageCount = images.length;
    int displayCount = imageCount > 9 ? 9 : imageCount;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4, childAspectRatio: 1.0),
      itemCount: displayCount,
      itemBuilder: (context, index) {
        if (imageCount > 9 && index == 8) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.network(images[index], fit: BoxFit.cover, errorBuilder: (c,e,s) => Container(color: Colors.grey.shade300)),
              Container(color: Colors.black54, child: Center(child: Text("+${imageCount - 8}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)))),
            ],
          );
        }
        return ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(images[index], fit: BoxFit.cover, errorBuilder: (c,e,s) => Container(color: Colors.grey.shade300)));
      },
    );
  }

  Widget postCard(post, index) {
    bool liked = post["liked"] ?? false;
    int likeCount = post["likeCount"] ?? 0;
    List images = post["images"] ?? [];

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => PostDetailPage(post: post, postIndex: index, isFromMyPost: true)))
            .then((_) => loadData());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(bottom: 10),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(12))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: Colors.grey.shade200,
                //  彻底废弃本地图片兜底
                backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey, size: 30) : null,
              ),
              title: Text(nickname.isNotEmpty ? nickname : "我", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.orange)),
              subtitle: Text(post["time"] ?? ""),
              trailing: PopupMenuButton(
                itemBuilder: (context) => [const PopupMenuItem(value: "delete", child: Text("删除"))],
                onSelected: (value) { if (value == "delete") deletePost(index); },
              ),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: ExpandableTextWidget(post["content"] ?? "", maxLines: 3)),
            const SizedBox(height: 10),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: buildImageGrid(images)),
            if (post["location"] != null && post["location"].toString().isNotEmpty)
              Padding(padding: const EdgeInsets.all(16), child: Row(children: [const Icon(Icons.location_on, size: 16, color: Colors.grey), const SizedBox(width: 6), Text(post["location"], style: const TextStyle(color: Colors.grey, fontSize: 13))])),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Row(children: [const Icon(Icons.chat, size: 20), const SizedBox(width: 6), Text("${post["comments"]?.length ?? 0}", style: const TextStyle(fontSize: 14))]),
                StatefulBuilder(
                  builder: (context, setState) {
                    return GestureDetector(
                      onTap: () async {
                        setState(() {
                          liked = !liked;
                          if (liked) likeCount++; else likeCount--;
                          post["liked"] = liked;
                          post["likeCount"] = likeCount;
                        });
                      },
                      child: Row(children: [Icon(Icons.thumb_up, color: liked ? Colors.blue : Colors.grey, size: 20), const SizedBox(width: 6), Text("$likeCount", style: const TextStyle(fontSize: 14))]),
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
        final span = TextSpan(text: widget.text, style: const TextStyle(fontSize: 16));
        final painter = TextPainter(text: span, maxLines: widget.maxLines, textDirection: TextDirection.ltr)..layout(maxWidth: size.maxWidth);
        final overflow = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.text, maxLines: expanded ? null : widget.maxLines, overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
            if (overflow) GestureDetector(onTap: () => setState(() => expanded = !expanded), child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(expanded ? "收起" : "全文", style: const TextStyle(color: Colors.blue, fontSize: 14))))
          ],
        );
      },
    );
  }
}