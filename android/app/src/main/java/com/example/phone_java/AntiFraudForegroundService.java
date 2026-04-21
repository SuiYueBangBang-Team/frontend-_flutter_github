package com.example.phone_java;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.IBinder;
import android.telecom.TelecomManager;
import android.telephony.PhoneStateListener;
import android.telephony.TelephonyManager;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

public class AntiFraudForegroundService extends Service {

    private static final String TAG = "AntiFraudFGService";
    private static final String CHANNEL_ID = "anti_fraud_service_channel";
    private static final int NOTIFICATION_ID = 2;

    private static volatile boolean sRunning = false;

    private TelephonyManager telephonyManager;
    private PhoneStateListener phoneStateListener;
    private BroadcastReceiver dynamicPhoneStateReceiver;

    public static void start(Context context) {
        Intent intent = new Intent(context, AntiFraudForegroundService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    public static void stop(Context context) {
        context.stopService(new Intent(context, AntiFraudForegroundService.class));
    }

    public static boolean isRunning() {
        return sRunning;
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "🚀 反诈前台服务启动");
        sRunning = true;
        createNotificationChannel();
        startForeground(NOTIFICATION_ID, buildNotification());
        registerCallMonitor();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        Log.i(TAG, "🛑 反诈前台服务停止");
        sRunning = false;
        unregisterCallMonitor();
        super.onDestroy();
    }

    @SuppressWarnings("deprecation")
    private void registerCallMonitor() {
        telephonyManager = (TelephonyManager) getSystemService(TELEPHONY_SERVICE);
        if (telephonyManager == null) {
            Log.e(TAG, "TelephonyManager 不可用");
            return;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // API 31+: PhoneStateListener 不再提供号码，用动态 BroadcastReceiver 代替
            registerDynamicReceiver();
        } else {
            // API < 31: PhoneStateListener 直接提供来电号码
            phoneStateListener = new PhoneStateListener() {
                @Override
                public void onCallStateChanged(int state, String incomingNumber) {
                    if (state == TelephonyManager.CALL_STATE_RINGING
                            && incomingNumber != null && !incomingNumber.isEmpty()) {
                        Log.i(TAG, "📞 [PhoneStateListener] 来电: " + incomingNumber);
                        handleIncomingCall(incomingNumber);
                    }
                }
            };
            telephonyManager.listen(phoneStateListener, PhoneStateListener.LISTEN_CALL_STATE);
            Log.i(TAG, "✅ PhoneStateListener 已注册");
        }
    }

    private void registerDynamicReceiver() {
        dynamicPhoneStateReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (!TelephonyManager.ACTION_PHONE_STATE_CHANGED.equals(intent.getAction())) return;
                String state = intent.getStringExtra(TelephonyManager.EXTRA_STATE);
                if (!TelephonyManager.EXTRA_STATE_RINGING.equals(state)) return;
                String number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER);
                if (number == null || number.isEmpty()) return;
                Log.i(TAG, "📞 [动态Receiver] 来电: " + number);
                handleIncomingCall(number);
            }
        };
        IntentFilter filter = new IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(dynamicPhoneStateReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(dynamicPhoneStateReceiver, filter);
        }
        Log.i(TAG, "✅ 动态 PhoneState Receiver 已注册 (API 31+)");
    }

    @SuppressWarnings("deprecation")
    private void unregisterCallMonitor() {
        if (phoneStateListener != null && telephonyManager != null) {
            telephonyManager.listen(phoneStateListener, PhoneStateListener.LISTEN_NONE);
            phoneStateListener = null;
        }
        if (dynamicPhoneStateReceiver != null) {
            try { unregisterReceiver(dynamicPhoneStateReceiver); } catch (Exception ignored) {}
            dynamicPhoneStateReceiver = null;
        }
    }

    private void handleIncomingCall(String phoneNumber) {
        String blockReason = AntiFraudUtils.shouldBlockCall(this, phoneNumber);
        if (blockReason != null) {
            Log.w(TAG, "🚫 [前台服务] 命中拦截规则，挂断: " + phoneNumber);
            AntiFraudUtils.recordBlockedCall(this, phoneNumber, blockReason);
            endIncomingCall();
        } else {
            Log.d(TAG, "✅ [前台服务] 放行: " + phoneNumber);
        }
    }

    @SuppressWarnings("deprecation")
    private void endIncomingCall() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            TelecomManager tm = (TelecomManager) getSystemService(TELECOM_SERVICE);
            if (tm != null) {
                try {
                    boolean ended = tm.endCall();
                    Log.i(TAG, "endCall() 结果: " + ended);
                } catch (SecurityException e) {
                    Log.e(TAG, "endCall() 失败，缺少 ANSWER_PHONE_CALLS 权限", e);
                }
            }
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID, "反诈来电拦截", NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("保持反诈来电拦截服务运行");
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) nm.createNotificationChannel(channel);
        }
    }

    private Notification buildNotification() {
        Intent notificationIntent = new Intent(this, MainActivity.class);
        PendingIntent pi = PendingIntent.getActivity(
                this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE);
        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("反诈卫士运行中")
                .setContentText("正在保护您的来电安全")
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentIntent(pi)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build();
    }
}
