package com.example.phone_java;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.PixelFormat;
import android.os.Build;
import android.util.Log;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.TextView;

import org.json.JSONObject;

import java.io.IOException;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

/**
 * 跨屏反诈告警对话框 - 可以在任何应用上方显示
 */
public class SafetyWarningDialog {
    private static final String TAG = "SafetyDialog";
    private static final String FEEDBACK_URL = "http://10.96.97.231:9000/api/fraud/feedback";

    private static View dialogView;
    private static WindowManager windowManager;

    public static void show(Context context, String rawContent, String type, String advice) {
        if (dialogView != null) return; // 已经在显示了

        windowManager = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        LayoutInflater inflater = LayoutInflater.from(context);
        dialogView = inflater.inflate(R.layout.dialog_safety_warning, null);

        // 设置文本 (增加内容截断)
        ((TextView) dialogView.findViewById(R.id.tv_type)).setText("类型：" + type);
        String displayContent = rawContent.length() > 100 ? rawContent.substring(0, 100) + "..." : rawContent;
        ((TextView) dialogView.findViewById(R.id.tv_content)).setText("内容：" + displayContent);
        ((TextView) dialogView.findViewById(R.id.tv_advice)).setText("建议：疑似诈骗内容已同步至子女端，请留意提醒，勿轻易转账。");

        int layoutType;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            layoutType = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY;
        } else {
            layoutType = WindowManager.LayoutParams.TYPE_PHONE;
        }

        WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                layoutType,
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                PixelFormat.TRANSLUCENT
        );
        params.gravity = Gravity.CENTER;

        // 按钮逻辑：仅保留关闭
        dialogView.findViewById(R.id.btn_ignore).setOnClickListener(v -> close());

        try {
            windowManager.addView(dialogView, params);
        } catch (Exception e) {
            Log.e(TAG, "无法显示告警对话框，请检查悬浮窗权限", e);
            dialogView = null;
        }
    }

    private static void close() {
        if (dialogView != null && windowManager != null) {
            windowManager.removeView(dialogView);
            dialogView = null;
        }
    }

    private static void submitFeedback(Context context, String content, int confirm) {
        OkHttpClient client = new OkHttpClient();
        try {
            JSONObject json = new JSONObject();
            json.put("content", content);
            json.put("confirm", confirm);

            RequestBody body = RequestBody.create(
                    json.toString(),
                    MediaType.get("application/json; charset=utf-8")
            );

            SharedPreferences prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            String token = prefs.getString("flutter.token", "");

            Request request = new Request.Builder()
                    .url(FEEDBACK_URL)
                    .addHeader("Authorization", token)
                    .post(body)
                    .build();

            client.newCall(request).enqueue(new Callback() {
                @Override
                public void onFailure(Call call, IOException e) {
                    Log.e(TAG, "反馈提交失败: " + e.getMessage());
                }

                @Override
                public void onResponse(Call call, Response response) {
                    Log.i(TAG, "反馈提交成功: " + confirm);
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "构建反馈请求失败", e);
        }
    }
}
