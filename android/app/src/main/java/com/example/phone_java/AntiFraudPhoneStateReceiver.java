package com.example.phone_java;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.telecom.TelecomManager;
import android.telephony.TelephonyManager;
import android.util.Log;

/**
 * 降级方案：通过监听 PHONE_STATE 广播拦截来电。
 * 用于不支持 CallScreeningService / ROLE_CALL_SCREENING 的设备。
 */
public class AntiFraudPhoneStateReceiver extends BroadcastReceiver {
    private static final String TAG = "AntiFraudFallback";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!TelephonyManager.ACTION_PHONE_STATE_CHANGED.equals(intent.getAction())) {
            return;
        }

        String state = intent.getStringExtra(TelephonyManager.EXTRA_STATE);
        if (!TelephonyManager.EXTRA_STATE_RINGING.equals(state)) {
            return;
        }

        String phoneNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER);
        if (phoneNumber == null || phoneNumber.isEmpty()) {
            return;
        }

        Log.i(TAG, "来电检测(降级模式): " + phoneNumber);

        String blockReason = AntiFraudUtils.shouldBlockCall(context, phoneNumber);
        if (blockReason != null) {
            Log.w(TAG, "命中拦截规则，尝试挂断: " + phoneNumber);
            AntiFraudUtils.recordBlockedCall(context, phoneNumber, blockReason);
            endCall(context);
        } else {
            Log.d(TAG, "审核通过，放行: " + phoneNumber);
        }
    }

    private void endCall(Context context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            TelecomManager telecomManager = (TelecomManager) context.getSystemService(Context.TELECOM_SERVICE);
            if (telecomManager != null) {
                try {
                    telecomManager.endCall();
                    Log.i(TAG, "已通过 TelecomManager 挂断来电");
                } catch (SecurityException e) {
                    Log.e(TAG, "挂断失败，缺少 ANSWER_PHONE_CALLS 权限", e);
                }
            }
        }
    }
}
