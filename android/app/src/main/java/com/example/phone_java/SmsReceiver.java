package com.example.phone_java;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.provider.Settings;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.telephony.SmsMessage;
import android.util.Log;

import org.json.JSONObject;

import java.io.IOException;
import java.util.concurrent.TimeUnit;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

public class SmsReceiver extends BroadcastReceiver {
    private static final String TAG = "SmsReceiver";
    private static final String BACKEND_URL = "http://10.96.97.231:9000/api/fraud/check";

    private static final OkHttpClient client = new OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .build();

    @Override
    public void onReceive(Context context, Intent intent) {
        Log.i(TAG, "▶▶▶ [Step1] SmsReceiver.onReceive 触发, action=" + intent.getAction());
        Bundle bundle = intent.getExtras();
        if (bundle == null) {
            Log.e(TAG, "✗ [Step1] bundle 为 null，广播无数据");
            return;
        }

        Object[] pdus = (Object[]) bundle.get("pdus");
        String format = bundle.getString("format");
        Log.i(TAG, "[Step1] pdus数量=" + (pdus == null ? "null" : pdus.length) + ", format=" + format);
        if (pdus == null) return;

        StringBuilder fullMessage = new StringBuilder();
        String sender = "";
        for (Object pdu : pdus) {
            SmsMessage msg = SmsMessage.createFromPdu((byte[]) pdu, format);
            if (msg == null) continue;
            if (sender.isEmpty()) sender = msg.getDisplayOriginatingAddress();
            fullMessage.append(msg.getMessageBody());
        }

        if (fullMessage.length() == 0) {
            Log.e(TAG, "✗ [Step1] 短信内容为空");
            return;
        }

        String content = "【" + sender + "】" + fullMessage;
        Log.i(TAG, "✓ [Step1] 短信解析成功: " + content);
        checkFraud(context, content);
    }

    private void checkFraud(Context context, String content) {
        try {
            SharedPreferences prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            String rawToken = prefs.getString("flutter.token", "");
            String token = rawToken != null ? rawToken.replace("\"", "").trim() : "";
            Log.i(TAG, "[Step2] token状态: " + (token.isEmpty() ? "❌ 为空！用户未登录或token未写入" : "✓ 长度=" + token.length()));

            JSONObject json = new JSONObject();
            json.put("content", content);

            Log.i(TAG, "[Step3] 准备请求后端: " + BACKEND_URL);
            RequestBody body = RequestBody.create(json.toString(), MediaType.parse("application/json; charset=utf-8"));
            Request request = new Request.Builder()
                    .url(BACKEND_URL)
                    .addHeader("Authorization", token)
                    .post(body)
                    .build();

            client.newCall(request).enqueue(new Callback() {
                @Override
                public void onFailure(Call call, IOException e) {
                    Log.e(TAG, "✗ [Step3] 网络请求失败（检查手机与服务器是否同一WiFi）: " + e.getMessage());
                }

                @Override
                public void onResponse(Call call, Response response) throws IOException {
                    Log.i(TAG, "[Step4] 后端响应码: " + response.code());
                    if (!response.isSuccessful() || response.body() == null) {
                        Log.e(TAG, "✗ [Step4] 响应异常或body为null, code=" + response.code());
                        return;
                    }
                    try {
                        String respStr = response.body().string();
                        Log.i(TAG, "[Step4] 响应内容: " + respStr);
                        JSONObject outer = new JSONObject(respStr);
                        int code = outer.getInt("code");
                        if (code != 200) {
                            Log.e(TAG, "✗ [Step4] 业务code非200: " + code + "（可能token无效，userId=null）");
                            return;
                        }
                        JSONObject data = outer.getJSONObject("data");
                        boolean isSuspect = data.optBoolean("isSuspect", false);
                        int riskScore = data.optInt("riskScore", 0);
                        Log.i(TAG, "[Step5] isSuspect=" + isSuspect + ", riskScore=" + riskScore);
                        if (isSuspect || riskScore >= 60) {
                            String msg = data.optString("warningMessage", "发现疑似诈骗短信，请提高警惕！");
                            String type = data.optString("fraudType", "电信诈骗");
                            Log.w(TAG, "🚨 [Step6] 触发弹窗预警! type=" + type);
                            new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Settings.canDrawOverlays(context)) {
                                    SafetyWarningDialog.show(context, content, type, msg);
                                } else {
                                    Log.w(TAG, "⚠️ [Step6] 无悬浮窗权限，改用系统通知");
                                    showFraudNotification(context, type, msg);
                                }
                            });
                        } else {
                            Log.i(TAG, "✓ [Step5] 内容安全，无需预警");
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "✗ [Step4] 解析响应失败", e);
                    }
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "✗ [Step2] 构建请求失败", e);
        }
    }

    private void showFraudNotification(Context context, String type, String msg) {
        String channelId = "fraud_alert";
        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(channelId, "反诈预警", NotificationManager.IMPORTANCE_HIGH);
            channel.enableVibration(true);
            nm.createNotificationChannel(channel);
        }
        Intent intent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        PendingIntent pi = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE);
        android.app.Notification notification = new androidx.core.app.NotificationCompat.Builder(context, channelId)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("⚠️ 反诈预警：" + type)
                .setContentText(msg)
                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build();
        nm.notify(9001, notification);
    }
}
