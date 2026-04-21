package com.example.phone_java;

import android.net.Uri;
import android.os.Build;
import android.telecom.Call;
import android.telecom.CallScreeningService;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;

/**
 * 反诈来电拦截服务 - 基于官方 CallScreeningService 实现
 */
@RequiresApi(api = Build.VERSION_CODES.Q)
public class AntiFraudCallService extends CallScreeningService {
    private static final String TAG = "AntiFraudCallService";

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "🚀 [拦截服务] 服务实例已创建 (onCreate) - 系统已准备好进行来电审核");
    }

    @Override
    public void onScreenCall(@NonNull Call.Details callDetails) {
        // 1. 只有呼入电话才处理
        if (callDetails.getCallDirection() != Call.Details.DIRECTION_INCOMING) {
            respondToCall(callDetails, new CallResponse.Builder().build());
            return;
        }

        // 2. 提取电话号码
        String phoneNumber = "";
        Uri handle = callDetails.getHandle();
        if (handle != null) {
            phoneNumber = handle.getSchemeSpecificPart();
        }

        Log.i(TAG, "📞 [来电审核] 收到呼入电话: " + phoneNumber);

        // 3. 调用核心过滤工具类进行判定
        String blockReason = AntiFraudUtils.shouldBlockCall(this, phoneNumber);

        // 4. 执行决策
        CallResponse.Builder responseBuilder = new CallResponse.Builder();
        if (blockReason != null) {
            Log.w(TAG, "🚫 [拦截执行] 命中反诈规则，正在拦截并挂断: " + phoneNumber);
            AntiFraudUtils.recordBlockedCall(this, phoneNumber, blockReason);
            responseBuilder.setDisallowCall(true)            // 不允许接听
                           .setRejectCall(true)              // 直接拒绝
                           .setSkipCallLog(false)           // 依然记录到通话记录（方便老人查看/回拨）
                           .setSkipNotification(true);      // 不显示通知
        } else {
            Log.d(TAG, "✅ [安全放行] 审核通过: " + phoneNumber);
        }

        respondToCall(callDetails, responseBuilder.build());
    }
}
