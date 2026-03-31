package com.example.phone_java;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.graphics.PixelFormat;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.Log;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.ImageView;

import androidx.core.app.NotificationCompat;

public class FloatWindowService extends Service {

    private static final String TAG = "FloatWindow";
    private static final String CHANNEL_ID = "float_window_channel";
    private static final long CLICK_DEBOUNCE_MS = 1000; // 1秒内防抖

    private WindowManager windowManager;
    private View floatView;
    private WindowManager.LayoutParams params;
    private long lastClickTime = 0;

    public static void show(Context context) {
        Intent intent = new Intent(context, FloatWindowService.class);
        intent.setAction("ACTION_SHOW");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    public static void hide(Context context) {
        Intent intent = new Intent(context, FloatWindowService.class);
        intent.setAction("ACTION_HIDE");
        context.startService(intent);
    }

    public static void updateRecordingState(Context context, boolean recording) {
        Intent intent = new Intent(context, FloatWindowService.class);
        intent.setAction("ACTION_UPDATE_RECORDING");
        intent.putExtra("recording", recording);
        context.startService(intent);
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        Log.d(TAG, "=== onCreate 悬浮窗服务启动 ===");

        // 检查悬浮窗权限（Android 6.0+ 必须用户授权）
        if (!Settings.canDrawOverlays(this)) {
            Log.w(TAG, "=== 缺少 SYSTEM_ALERT_WINDOW 权限，尝试请求 ===");
            Intent overlayIntent = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION);
            overlayIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(overlayIntent);
            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();
            return;
        }

        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        createNotificationChannel();
        startForeground(1, buildNotification());

        int layoutType;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            layoutType = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY;
        } else {
            layoutType = WindowManager.LayoutParams.TYPE_PHONE;
        }

        params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                layoutType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
        );
        params.gravity = Gravity.TOP | Gravity.END;
        params.x = 20;
        params.y = 300;

        floatView = LayoutInflater.from(this).inflate(R.layout.float_window, null);

        FrameLayout root = floatView.findViewById(R.id.float_root);
        root.setClickable(true);
        root.setOnTouchListener(new View.OnTouchListener() {
            private int initialX, initialY;
            private float initialTouchX, initialTouchY;
            private boolean isDragging = false;
            private static final int CLICK_THRESHOLD = 30;

            @Override
            public boolean onTouch(View v, MotionEvent event) {
                int action = event.getAction();
                Log.d(TAG, ">>> onTouch action=" + actionToString(action)
                        + ", rawX=" + event.getRawX() + ", rawY=" + event.getRawY());

                switch (action) {
                    case MotionEvent.ACTION_DOWN:
                        initialX = params.x;
                        initialY = params.y;
                        initialTouchX = event.getRawX();
                        initialTouchY = event.getRawY();
                        isDragging = false;
                        Log.d(TAG, "    [DOWN] 初始位置=(" + initialX + "," + initialY + ")");
                        return true;

                    case MotionEvent.ACTION_MOVE: {
                        float dx = event.getRawX() - initialTouchX;
                        float dy = event.getRawY() - initialTouchY;
                        float distance = (float) Math.sqrt(dx * dx + dy * dy);

                        if (!isDragging && distance > CLICK_THRESHOLD) {
                            isDragging = true;
                            Log.d(TAG, "    [MOVE] 触发拖拽，移动距离=" + distance);
                        }
                        if (isDragging) {
                            params.x = initialX + (int) dx;
                            params.y = initialY + (int) dy;
                            windowManager.updateViewLayout(floatView, params);
                            Log.d(TAG, "    [MOVE] 更新位置=(" + params.x + "," + params.y + ")");
                        } else {
                            Log.d(TAG, "    [MOVE] 未达拖拽阈值 distance=" + distance);
                        }
                        return true;
                    }

                    case MotionEvent.ACTION_UP: {
                        long now = SystemClock.elapsedRealtime();
                        Log.d(TAG, "    [UP] isDragging=" + isDragging + ", 距上次点击=" + (now - lastClickTime) + "ms");

                        if (!isDragging) {
                            if (now - lastClickTime < CLICK_DEBOUNCE_MS) {
                                Log.w(TAG, "    [UP] 防抖拦截，忽略此次点击");
                            } else {
                                lastClickTime = now;
                                Log.d(TAG, "    [UP] 执行点击，跳转 App");
                                Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
                                if (launchIntent != null) {
                                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                                            | Intent.FLAG_ACTIVITY_CLEAR_TOP
                                            | Intent.FLAG_ACTIVITY_SINGLE_TOP);
                                    Log.d(TAG, "    [UP] 调用 startActivity");
                                    startActivity(launchIntent);
                                } else {
                                    Log.e(TAG, "    [UP] launchIntent 为空！");
                                }
                            }
                        }
                        return true;
                    }

                    case MotionEvent.ACTION_CANCEL:
                        Log.w(TAG, "    [CANCEL] 触摸被系统取消");
                        return true;
                }
                return true;
            }
        });

        try {
            windowManager.addView(floatView, params);
            Log.d(TAG, "=== onCreate 完成，悬浮窗已显示 ===");
        } catch (Exception e) {
            Log.e(TAG, "=== 悬浮窗添加失败: " + e.getClass().getSimpleName() + ": " + e.getMessage() + " ===");
            Log.e(TAG, "如果使用模拟器，请确保已授予 SYSTEM_ALERT_WINDOW 权限（需在设置中手动开启）");
            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();
        }
    }

    private String actionToString(int action) {
        switch (action) {
            case MotionEvent.ACTION_DOWN: return "DOWN";
            case MotionEvent.ACTION_MOVE: return "MOVE";
            case MotionEvent.ACTION_UP: return "UP";
            case MotionEvent.ACTION_CANCEL: return "CANCEL";
            default: return "UNKNOWN(" + action + ")";
        }
    }

    private void setRecordingState(boolean recording) {
        if (floatView == null) return;
        ImageView btn = floatView.findViewById(R.id.float_btn);
        if (recording) {
            btn.setBackgroundResource(R.drawable.float_circle_bg_recording);
        } else {
            btn.setBackgroundResource(R.drawable.float_circle_bg);
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.d(TAG, "onStartCommand: action=" + (intent == null ? "null" : intent.getAction()));
        if (intent == null) return START_STICKY;

        String action = intent.getAction();
        if ("ACTION_HIDE".equals(action)) {
            if (floatView != null && windowManager != null) {
                windowManager.removeView(floatView);
                floatView = null;
            }
            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();
        } else if ("ACTION_UPDATE_RECORDING".equals(action)) {
            boolean recording = intent.getBooleanExtra("recording", false);
            setRecordingState(recording);
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        Log.d(TAG, "=== onDestroy 悬浮窗服务销毁 ===");
        if (floatView != null && windowManager != null) {
            windowManager.removeView(floatView);
        }
        super.onDestroy();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID, "悬浮窗服务", NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("保持悬浮窗在后台运行");
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) nm.createNotificationChannel(channel);
        }
    }

    private Notification buildNotification() {
        Intent notificationIntent = new Intent(this, MainActivity.class);
        PendingIntent pi = PendingIntent.getActivity(
                this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE);
        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("岁悦帮帮")
                .setContentText("点击悬浮窗回到应用")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setContentIntent(pi)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build();
    }
}
