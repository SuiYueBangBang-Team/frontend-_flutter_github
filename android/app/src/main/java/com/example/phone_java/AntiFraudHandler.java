package com.example.phone_java;

import android.accessibilityservice.AccessibilityService;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

import org.json.JSONObject;

import java.io.IOException;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.TimeUnit;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

/**
 * 反诈核心处理器 - 负责抓取文本并调用后端 AI 进行风险核验
 */
public class AntiFraudHandler {
    private static final String TAG = "AntiFraudHandler";
    private static final String BACKEND_URL = "http://43.136.23.112:9000/api/fraud/check";

    private final OkHttpClient client = new OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .build();

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    
    // 自演化系统组件
    private ModelManager modelManager;
    private final LocalInferenceEngine localEngine = new LocalInferenceEngine();

    // 用于去重，避免对同一段文字反复检测
    private final Set<String> handledTexts = new HashSet<>();
    private long lastClearTime = System.currentTimeMillis();

    public void onAccessibilityEvent(AccessibilityService service, AccessibilityEvent event) {
        // 初始化模型管理器 (单例延迟加载)
        if (modelManager == null) {
            modelManager = new ModelManager(service);
            modelManager.checkForUpdates();
        }

        // 定期清理已处理列表 (60秒去重窗口，必须放在包含判断之前)
        if (System.currentTimeMillis() - lastClearTime > 60000) {
            handledTexts.clear();
            lastClearTime = System.currentTimeMillis();
            modelManager.checkForUpdates();
        }

        // 1. 提取文本内容
        String textContent = extractTextContent(event);
        if (textContent == null || textContent.length() < 6) {
            return;
        }

        if (handledTexts.contains(textContent)) {
            Log.v(TAG, "跳过重复内容 (60s防抖内): " + textContent);
            return;
        }
        handledTexts.add(textContent);

        Log.i(TAG, "🔍 [捕捉成功] 检测到新内容: " + textContent);

        // --- [创新点] 核心：本地 AI 预判逻辑 ---
        if (modelManager.getInterpreter() != null) {
            float localScore = localEngine.predict(modelManager.getInterpreter(), textContent);
            Log.d(TAG, "本地模型评分结果: " + localScore);
            if (localScore > 0.8) {
                Log.w(TAG, "🚨 [高危] 本地模型发现诈骗风险，立即预警！内容: " + textContent);
                showWarning(service, textContent, "本地 AI 判别", "系统离线识别出高风险话术，请小心！");
            }
        }

        // 2. 异步请求后端 AI (云端复核)
        Log.d(TAG, "准备向云端发起验证: " + BACKEND_URL);
        checkFraudWithBackend(service, textContent);
    }

    private String extractTextContent(AccessibilityEvent event) {
        if (event.getEventType() == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
            String pkg = event.getPackageName() != null ? event.getPackageName().toString() : "";
            // 不再强硬过滤短信应用包名，因为各个厂商、模拟器包名五花八门
            Log.d(TAG, "🔔 [通知事件] 来源包名: " + pkg);
            
            if (event.getText() != null && !event.getText().isEmpty()) {
                StringBuilder sb = new StringBuilder();
                for (CharSequence charSequence : event.getText()) {
                    sb.append(charSequence).append(" ");
                }
                String notificationText = sb.toString().trim();
                Log.d(TAG, "🔔 [通知事件] 内容捕捉: " + notificationText);
                return notificationText;
            }
        } else {
            // 处理窗口内容变化
            AccessibilityNodeInfo root = event.getSource();
            if (root == null) return null;
            
            StringBuilder sb = new StringBuilder();
            extractTextFromNode(root, sb, new HashSet<>()); // 传入 Set 进行局部去重
            return sb.toString().trim();
        }
        return null;
    }

    private void extractTextFromNode(AccessibilityNodeInfo node, StringBuilder sb, Set<String> localSet) {
        if (node == null) return;
        if (node.getText() != null) {
            String text = node.getText().toString().trim();
            // 核心优化：如果同一屏内已经处理过相同文本，则跳过，防止 [摘要, 详情] 重复拼接
            if (!text.isEmpty() && !localSet.contains(text)) {
                sb.append(text).append(" ");
                localSet.add(text);
            }
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            extractTextFromNode(node.getChild(i), sb, localSet);
        }
    }

    private void checkFraudWithBackend(Context context, String content) {
        try {
            JSONObject jsonRequest = new JSONObject();
            jsonRequest.put("content", content);

            // 获取本地保存的 Token (模拟 ApiClient.dart 的行为)
            SharedPreferences prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            // 核心修复：Flutter 存入的字符串在原生端读取时可能带有引中引（双引号），需要清理
            String rawToken = prefs.getString("flutter.token", "");
            String token = rawToken != null ? rawToken.replace("\"", "").trim() : "";
            
            if (token.isEmpty()) {
                Log.e(TAG, "❌ [鉴权失败] 未找到登录 Token，记录将无法关联用户！");
            } else {
                Log.d(TAG, "🔑 [鉴权中] 使用 Token: " + (token.length() > 10 ? token.substring(0, 10) + "..." : "short-token"));
            }

            RequestBody body = RequestBody.create(
                    jsonRequest.toString(),
                    MediaType.parse("application/json; charset=utf-8")
            );

            Request request = new Request.Builder()
                    .url(BACKEND_URL)
                    .addHeader("Authorization", token)
                    .post(body)
                    .build();

            client.newCall(request).enqueue(new Callback() {
                @Override
                public void onFailure(Call call, IOException e) {
                    Log.e(TAG, "❌ 云端 API 请求失败! 请检查电脑 IP (" + BACKEND_URL + ") 是否正确: " + e.getMessage());
                }

                @Override
                public void onResponse(Call call, Response response) throws IOException {
                    Log.d(TAG, "云端响应状态码: " + response.code());
                    if (response.isSuccessful() && response.body() != null) {
                        try {
                            String respStr = response.body().string();
                            Log.d(TAG, "详细响应内容: " + respStr);
                            JSONObject outer = new JSONObject(respStr);
                            if (outer.getInt("code") == 200) {
                                JSONObject data = outer.getJSONObject("data");
                                boolean isSuspect = data.optBoolean("isSuspect", false);
                                int riskScore = data.optInt("riskScore", 0);

                                if (isSuspect || riskScore >= 60) {
                                    String msg = data.optString("warningMessage", "发现疑似诈骗内容，请提高警惕！");
                                    String type = data.optString("fraudType", "电信诈骗");
                                    mainHandler.post(() -> showWarning(context, content, type, msg));
                                } else {
                                    Log.d(TAG, "云端复核通过：正常内容");
                                }
                            }
                        } catch (Exception e) {
                            Log.e(TAG, "解析反诈响应失败", e);
                        }
                    } else {
                        Log.e(TAG, "云端 API 响应异常, Code: " + response.code());
                    }
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "构建反诈请求失败", e);
        }
    }

    private void showWarning(Context context, String rawContent, String type, String warning) {
        Log.w(TAG, "！！！触发反诈告警！！！ 类型: " + type + ", 内容摘要: " + (rawContent.length() > 20 ? rawContent.substring(0, 20) + "..." : rawContent));
        // 这里调起全局悬浮窗对话框
        SafetyWarningDialog.show(context, rawContent, type, warning);
    }

}
