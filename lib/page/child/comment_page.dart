import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class CommentPage extends StatefulWidget {

  final int postIndex;

  const CommentPage({
    super.key,
    required this.postIndex
  });

  @override
  State<CommentPage> createState() => _CommentPageState();
}

class _CommentPageState extends State<CommentPage> {

  List postList = [];

  TextEditingController commentController =
  TextEditingController();

  String nickname = "";
  String avatarUrl = "";

  @override
  void initState() {

    super.initState();

    loadData();

  }

  loadData() async {

    final prefs =
    await SharedPreferences.getInstance();

    nickname =
        prefs.getString("nickname") ?? "用户";

    avatarUrl =
        prefs.getString("avatarUrl") ?? "";

    String? data =
    prefs.getString("postList");

    if(data!=null){

      postList=jsonDecode(data);

      for (var post in postList) {

        post["comments"] ??= [];

        for (var comment in post["comments"]) {

          comment["liked"] ??= false;

          comment["likeCount"] ??= 0;

          comment["time"] ??= "";

          comment["isAuthor"] ??= false;

        }

      }

    }

    setState(() {});

  }

  addComment() async {

    if(commentController.text.isEmpty) return;

    (postList[widget.postIndex]["comments"] ??= []).add({

      "name": nickname,

      "content": commentController.text,

      "time": DateTime.now().toString(),

      "likeCount": 0,

      "liked": false,

      "isAuthor": true

    });

    final prefs =
    await SharedPreferences.getInstance();

    await prefs.setString(
        "postList",
        jsonEncode(postList));

    commentController.clear();

    setState(() {});

  }

////////////
  /// 顶部帖子卡片（完全复刻发帖页UI + 预留后端接口）
////////////

  Widget buildPostHeader(){

    if(postList.isEmpty) return const SizedBox();

    var post = postList[widget.postIndex];

    return Container(

      margin: const EdgeInsets.symmetric(vertical:8),

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius: BorderRadius.circular(12),

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

////////////
          /// 头像 + 用户名 + 时间
////////////

          Row(

            children: [

              CircleAvatar(

                radius: 24,

                backgroundColor: Colors.grey.shade200,

                backgroundImage:

                avatarUrl.isNotEmpty

                    ? NetworkImage(

                    avatarUrl

                  /// TODO: 后端头像接口字段
                  /// post["avatarUrl"]

                )

                    : null,

                child:

                avatarUrl.isEmpty

                    ? const Icon(Icons.person,size:26)

                    : null,

              ),

              const SizedBox(width:12),

              Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Text(

                    post["nickname"]

                        /// TODO: 后端字段 nickname
                        ?? nickname,

                    style: const TextStyle(

                        fontSize:16,

                        fontWeight: FontWeight.bold

                    ),

                  ),

                  const SizedBox(height:4),

                  Text(

                    post["time"] != null &&

                        post["time"].toString().length >= 16

                        ?

                    post["time"]

                        .toString()

                        .substring(5,16)

                        :

                    "",

                    style: const TextStyle(

                        fontSize:12,

                        color: Colors.grey

                    ),

                  )

                ],

              )

            ],

          ),

////////////
          /// 正文
////////////

          const SizedBox(height:12),

          Text(

            post["content"]

                /// TODO: 后端字段 content

                ?? "",

            style: const TextStyle(

                fontSize:16

            ),

          ),

////////////
          /// 图片区域（最多3张）
////////////

          if(post["images"] != null &&

              post["images"].length > 0)

            Padding(

              padding:

              const EdgeInsets.only(top:12),

              child: Wrap(

                spacing:10,

                runSpacing:10,

                children: List.generate(

                  post["images"].length,

                      (index){

                    return ClipRRect(

                      borderRadius:

                      BorderRadius.circular(8),

                      child: Image.network(

                        post["images"][index],

                        /// TODO: 后端图片字段 images[]

                        width:110,

                        height:110,

                        fit: BoxFit.cover,

                      ),

                    );

                  },

                ),

              ),

            ),

////////////
          /// 定位信息
////////////

          if(post["location"] != null &&

              post["location"] != "")

            Padding(

              padding:

              const EdgeInsets.only(top:10),

              child: Row(

                children: [

                  const Icon(

                      Icons.location_on,

                      size:16,

                      color: Colors.grey

                  ),

                  const SizedBox(width:4),

                  Text(

                    post["location"],

                    /// TODO: 后端字段 location

                    style: const TextStyle(

                        color: Colors.grey,

                        fontSize:13

                    ),

                  )

                ],

              ),

            ),

////////////
          /// 分割线
////////////

          const SizedBox(height:6),

          Divider(

            color: Colors.grey.shade300,

            thickness: 1,

          )

        ],

      ),

    );

  }

////////////
  /// 评论列表
////////////

  Widget buildCommentList(){

    if(postList.isEmpty)
      return const SizedBox();

    List comments =
        postList[widget.postIndex]["comments"]
            ?? [];

    return ListView.builder(

      itemCount:
      comments.length,

      itemBuilder:
          (context,index){

        var c=
        comments[index];

        return Padding(

          padding:
          const EdgeInsets.symmetric(
              horizontal:12,
              vertical:8),

          child: Row(

            crossAxisAlignment:
            CrossAxisAlignment.start,

            children: [

              const CircleAvatar(
                radius:18,
                child:
                Icon(Icons.person),
              ),

              const SizedBox(width:10),

              Expanded(

                child: Column(

                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [

                    Row(

                      children: [

                        Text(

                          c["name"],

                          style:
                          const TextStyle(
                              fontWeight:
                              FontWeight.bold),

                        ),

                        if(c["isAuthor"])

                          Container(

                            margin:
                            const EdgeInsets.only(left:6),

                            padding:
                            const EdgeInsets.symmetric(
                                horizontal:6,
                                vertical:2),

                            decoration:
                            BoxDecoration(

                              color:
                              Colors.red,

                              borderRadius:
                              BorderRadius.circular(4),

                            ),

                            child:
                            const Text(

                              "作者",

                              style:
                              TextStyle(
                                  color:Colors.white,
                                  fontSize:10),

                            ),

                          )

                      ],

                    ),

                    const SizedBox(height:4),

                    Text(
                        c["content"]
                    ),

                    const SizedBox(height:6),

                    Row(

                      children: [

                        Text(

                          c["time"] != null &&
                              c["time"]
                                  .toString()
                                  .length>=16

                              ?

                          c["time"]
                              .toString()
                              .substring(5,16)

                              :

                          "",

                          style:
                          const TextStyle(
                              fontSize:12,
                              color:Colors.grey),

                        ),

                        const Spacer(),

                        GestureDetector(

                          onTap:()async{

                            c["liked"]=
                            !c["liked"];

                            if(c["liked"])

                              c["likeCount"]++;

                            else

                              c["likeCount"]--;

                            final prefs=
                            await SharedPreferences.getInstance();

                            await prefs.setString(

                                "postList",

                                jsonEncode(postList)

                            );

                            setState(() {});

                          },

                          child:

                          Row(

                            children: [

                              Icon(

                                c["liked"]

                                    ?

                                Icons.favorite

                                    :

                                Icons.favorite_border,

                                size:18,

                                color:

                                c["liked"]

                                    ?

                                Colors.red

                                    :

                                Colors.grey,

                              ),

                              const SizedBox(width:4),

                              Text(
                                  "${c["likeCount"]}"
                              )

                            ],

                          ),

                        )

                      ],

                    )

                  ],

                ),

              )

            ],

          ),

        );

      },

    );

  }

////////////
  /// 输入框
////////////

  Widget buildInputBar(){

    return Container(

      color:Colors.white,

      padding:
      const EdgeInsets.symmetric(
          horizontal:10,
          vertical:6),

      child:

      Row(

        children: [

          Expanded(

            child:

            TextField(

              controller:
              commentController,

              decoration:
              const InputDecoration(

                hintText:"写评论...",

                border:
                InputBorder.none,

              ),

            ),

          ),

          IconButton(

            icon:
            const Icon(Icons.send),

            onPressed:
            addComment,

          )

        ],

      ),

    );

  }

////////////
  /// 页面主体
////////////

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor:
      const Color(0xFFF5F5F5),

      appBar:

      AppBar(
          title:
          const Text("评论")
      ),

      body:

      Column(

        children: [

          buildPostHeader(),

          Expanded(
              child:
              buildCommentList()
          ),

          buildInputBar()

        ],

      ),

    );

  }

}