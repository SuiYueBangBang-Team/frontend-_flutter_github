package com.example.phone_java;

import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import android.provider.ContactsContract;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.HashSet;
import java.util.Locale;
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
 * 反诈判定工具类 - 处理核心拦截逻辑
 */
public class AntiFraudUtils {
    private static final String TAG = "AntiFraudUtils";
    private static final String REPORT_URL = "http://10.96.97.231:9000/api/fraud/report-intercept";

    private static final OkHttpClient client = new OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .build();

    // 💡 模拟黑名单：常见骚扰/诈骗号码号段头
    private static final Set<String> HARASSMENT_PREFIXES = new HashSet<>(Arrays.asList(
            "400", "800", "95", "96"
    ));

    private static final int MAX_RECORDS = 100;

    /**
     * 核心决策引擎：根据各种开关决定是否拦截
     * @return null = 放行，非 null = 拦截原因
     */
    public static String shouldBlockCall(Context context, String phoneNumber) {
        if (phoneNumber == null || phoneNumber.isEmpty()) {
            Log.d(TAG, "🔍 [拦截自检] 号码为空，直接放行");
            return null;
        }

        SharedPreferences prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);

        // 1. 境外来电拦截
        boolean overseasEnabled = prefs.getBoolean("flutter.overseasIntercept", false);
        Log.d(TAG, "🔍 [拦截自检] 境外过滤器状态: " + overseasEnabled);
        if (overseasEnabled && isInternationalNumber(phoneNumber)) {
            Log.w(TAG, "🚨 [拦截决策] 境外号码检测，执行拦截: " + phoneNumber);
            return "境外来电拦截";
        }

        // 2. 非通讯录拦截 (陌生人)
        boolean contactOnlyEnabled = prefs.getBoolean("flutter.contactOnly", false);
        Log.d(TAG, "🔍 [拦截自检] 非通讯录过滤器状态: " + contactOnlyEnabled);
        if (contactOnlyEnabled) {
            boolean inContacts = isNumberInContacts(context, phoneNumber);
            Log.d(TAG, "🔍 [拦截自检] 号码 [" + phoneNumber + "] 是否在通讯录: " + inContacts);
            if (!inContacts) {
                Log.w(TAG, "🚨 [拦截决策] 陌生号码且开启非通讯录拦截，执行拦截: " + phoneNumber);
                return "非通讯录拦截";
            }
        }

        // 3. 标记号码拦截 (骚扰/诈骗)
        boolean markEnabled = prefs.getBoolean("flutter.markIntercept", false);
        Log.d(TAG, "🔍 [拦截自检] 标记号拦截状态: " + markEnabled);
        if (markEnabled) {
            if (isHarassmentNumber(phoneNumber)) {
                Log.w(TAG, "🚨 [拦截决策] 命中骚扰号段库，执行拦截: " + phoneNumber);
                return "标记号码拦截";
            }
        }

        Log.d(TAG, "✅ [拦截决策] 未命中规则，正常放行: " + phoneNumber);
        return null;
    }

    /**
     * 保存拦截记录到 SharedPreferences（JSON 数组）
     */
    public static void recordBlockedCall(Context context, String phoneNumber, String blockType) {
        try {
            SharedPreferences prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            String existing = prefs.getString("flutter.blockedCallRecords", "[]");
            JSONArray records = new JSONArray(existing);

            JSONObject record = new JSONObject();
            record.put("number", phoneNumber);
            record.put("time", new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.CHINA).format(new Date()));
            record.put("type", blockType);
            record.put("synced", false); // 默认未同步

            // 新记录插入头部
            JSONArray updated = new JSONArray();
            updated.put(record);
            for (int i = 0; i < records.length() && i < MAX_RECORDS - 1; i++) {
                updated.put(records.get(i));
            }

            prefs.edit().putString("flutter.blockedCallRecords", updated.toString()).apply();
            Log.i(TAG, "📝 [拦截自查] 本地已存成功: " + phoneNumber + ", 记录总数: " + updated.length());

            // ✨ [增强] 触发即时同步
            uploadInterceptRecord(context, phoneNumber, blockType);

        } catch (Exception e) {
            Log.e(TAG, "❌ [拦截自查] 保存失败", e);
        }
    }

    /**
     * 将拦截记录同步到云端
     */
    private static void uploadInterceptRecord(Context context, String phoneNumber, String blockType) {
        try {
            SharedPreferences prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            String rawToken = prefs.getString("flutter.token", "");
            String token = rawToken != null ? rawToken.replace("\"", "").trim() : "";

            Log.d(TAG, "🛡️ [拦截同步] 准备上报. Token 预览: " + (token.length() > 5 ? token.substring(0, 5) + "..." : "empty"));

            if (token.isEmpty()) {
                Log.w(TAG, "⚠️ [拦截同步] Token 为空，跳过本次上报 (稍后由 Flutter 端巡检补发)");
                return;
            }

            JSONObject jsonBody = new JSONObject();
            jsonBody.put("phoneNumber", phoneNumber);
            jsonBody.put("blockType", blockType);
            jsonBody.put("time", new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.CHINA).format(new Date()));

            RequestBody body = RequestBody.create(
                    jsonBody.toString(),
                    MediaType.parse("application/json; charset=utf-8")
            );

            Request request = new Request.Builder()
                    .url(REPORT_URL)
                    .addHeader("Authorization", token)
                    .post(body)
                    .build();

            Log.d(TAG, "🛡️ [拦截同步] 请求 URL: " + REPORT_URL + ", Body: " + jsonBody.toString());

            client.newCall(request).enqueue(new Callback() {
                @Override
                public void onFailure(Call call, IOException e) {
                    Log.e(TAG, "❌ [拦截同步] 网络请求彻底失败 (请确认手机 WiFi 是否跨网段): " + e.getMessage());
                }

                @Override
                public void onResponse(Call call, Response response) throws IOException {
                    Log.d(TAG, "🛡️ [拦截同步] 服务器响响应码: " + response.code());
                    if (response.isSuccessful()) {
                        Log.i(TAG, "✅ [拦截同步] 实时上报成功: " + phoneNumber);
                        markRecordSynced(context, phoneNumber);
                    } else {
                        String errorBody = response.body() != null ? response.body().string() : "no body";
                        Log.e(TAG, "❌ [拦截同步] 服务器拒绝上报, Body: " + errorBody);
                    }
                    response.close();
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "❌ [拦截同步] 构建流程异常", e);
        }
    }

    private static void markRecordSynced(Context context, String phoneNumber) {
        try {
            SharedPreferences prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            String existing = prefs.getString("flutter.blockedCallRecords", "[]");
            JSONArray records = new JSONArray(existing);
            for (int i = 0; i < records.length(); i++) {
                JSONObject r = records.getJSONObject(i);
                if (phoneNumber.equals(r.optString("number")) && !r.optBoolean("synced", false)) {
                    r.put("synced", true);
                    break;
                }
            }
            prefs.edit().putString("flutter.blockedCallRecords", records.toString()).apply();
        } catch (Exception e) {
            Log.e(TAG, "❌ [拦截同步] 更新 synced 状态失败", e);
        }
    }

    /**
     * 判定是否为境外号码
     * 规则：以 + 或 00 开头，且非 +86 / 0086
     */
    public static boolean isInternationalNumber(String phoneNumber) {
        if (phoneNumber.startsWith("+")) {
            return !phoneNumber.startsWith("+86");
        }
        if (phoneNumber.startsWith("00")) {
            return !phoneNumber.startsWith("0086");
        }
        return false;
    }

    /**
     * 判定是否在系统通讯录中
     */
    public static boolean isNumberInContacts(Context context, String phoneNumber) {
        if (phoneNumber == null || phoneNumber.isEmpty()) return false;

        Uri uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(phoneNumber));
        String[] projection = new String[]{ContactsContract.PhoneLookup.DISPLAY_NAME};

        try (Cursor cursor = context.getContentResolver().query(uri, projection, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                String name = cursor.getString(0);
                Log.d(TAG, "👤 [通讯录检索] 匹配成功: " + name + " (号码: " + phoneNumber + ")");
                return true;
            } else {
                Log.d(TAG, "👤 [通讯录检索] 无匹配结果 (号码: " + phoneNumber + ")");
            }
        } catch (SecurityException se) {
            Log.e(TAG, "❌ [通讯录检索] 缺少 READ_CONTACTS 权限!", se);
        } catch (Exception e) {
            Log.e(TAG, "❌ [通讯录检索] 查询异常", e);
        }
        return false;
    }

    /**
     * 判定是否为疑似骚扰号码 (简化版逻辑)
     */
    private static boolean isHarassmentNumber(String number) {
        // 去除前缀后的真实起始
        String cleanNumber = number.replace("+86", "").replace("0086", "").trim();
        for (String prefix : HARASSMENT_PREFIXES) {
            if (cleanNumber.startsWith(prefix)) return true;
        }
        return false;
    }
}
