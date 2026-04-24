package com.example.phone_java;

import android.accessibilityservice.AccessibilityService;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import java.util.List;
public class PinduoduoAutoService {

    private static final String TAG = "PinduoduoAuto";
    private static final String PKG_PIN = "com.xunmeng.pinduoduo";
    private static final String ID_COMMON = "com.xunmeng.pinduoduo:id/pdd";

    private static final int STEP_IDLE                  = 0;
    private static final int STEP_CLICK_HOME_SEARCH     = 1;
    private static final int STEP_INPUT_KEYWORD         = 2;
    private static final int STEP_CLICK_SEARCH_BUTTON   = 3;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private int step = STEP_IDLE;
    private String targetKeyword = "";
    private long lastHandledRequestId = -1L;
    private long stepStartTime = 0L;
    private AccessibilityService serviceInstance;

    public void handleEvent(AccessibilityService service, AccessibilityEvent event) {
        this.serviceInstance = service;

        long pendingRequestId = getPendingRequestId(service);
        String pendingKeyword = getPendingKeyword(service);

        if (pendingRequestId > 0 && pendingRequestId != lastHandledRequestId) {
            if (!pendingKeyword.isEmpty()) {
                targetKeyword = pendingKeyword;
                lastHandledRequestId = pendingRequestId;
                stepStartTime = System.currentTimeMillis();
                step = STEP_CLICK_HOME_SEARCH;
                Log.d(TAG, "========== 开始搜索：" + targetKeyword + " ==========");
            }
        }

        if (step == STEP_IDLE) return;
        if (System.currentTimeMillis() - stepStartTime > 20000) {
            Log.e(TAG, "执行超时，重置任务");
            clearPendingTask(service);
            step = STEP_IDLE;
            return;
        }

        handler.removeCallbacks(stateMachineRunnable);
        handler.postDelayed(stateMachineRunnable, 600);
    }

    private final Runnable stateMachineRunnable = new Runnable() {
        @Override
        public void run() {
            if (serviceInstance == null) return;
            AccessibilityNodeInfo root = serviceInstance.getRootInActiveWindow();
            if (root == null) return;

            switch (step) {
                case STEP_CLICK_HOME_SEARCH:
                    if (AccessibilityUtils.clickByViewId(root, ID_COMMON)
                            || AccessibilityUtils.clickByAnyText(root, "搜索")
                            || AccessibilityUtils.clickByAnyDesc(root, "搜索")) {
                        step = STEP_INPUT_KEYWORD;
                        handler.postDelayed(this, 1000);
                        return;
                    }
                    break;

                case STEP_INPUT_KEYWORD:
                    AccessibilityNodeInfo input = AccessibilityUtils.findFirstNodeByViewId(root, ID_COMMON);
                    if (input == null) {
                        input = AccessibilityUtils.findFirstNodeByClass(root, "android.widget.EditText");
                    }

                    if (input != null && PKG_PIN.equals(input.getPackageName())) {
                        if (AccessibilityUtils.inputText(input, targetKeyword)) {
                            step = STEP_CLICK_SEARCH_BUTTON;
                            handler.postDelayed(this, 800);
                            return;
                        }
                    }
                    break;

                case STEP_CLICK_SEARCH_BUTTON:
                    // 1. 尝试寻找文本为 "搜索" 的节点
                    List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByText("搜索");
                    boolean clicked = false;
                    if (nodes != null && !nodes.isEmpty()) {
                        for (AccessibilityNodeInfo node : nodes) {
                            // 过滤一下，确保它是那个按钮而不是搜索历史
                            if ("android.widget.TextView".equals(node.getClassName().toString())) {
                                // 优先尝试方案一：递归点父容器
                                if (clickNodeOrParent(node)) {
                                    clicked = true;
                                    Log.d(TAG, "✅ 通过父容器点击成功");
                                    break;
                                }
                                // 如果方案一失败，尝试方案二：坐标点击
                                clickByCoordinates(serviceInstance, node);
                                clicked = true;
                                Log.d(TAG, "✅ 通过坐标模拟点击成功");
                                break;
                            }
                        }
                    }

                    if (clicked) {
                        step = STEP_IDLE;
                        clearPendingTask(serviceInstance);
                    }
                    break;
            }

            handler.postDelayed(this, 500);
        }
    };
    // 强制坐标点击
    public void clickByCoordinates(AccessibilityService service, AccessibilityNodeInfo node) {
        if (node == null) return;
        android.graphics.Rect rect = new android.graphics.Rect();
        node.getBoundsInScreen(rect); // 获取在屏幕上的坐标范围
        int x = rect.centerX();
        int y = rect.centerY();

        android.accessibilityservice.GestureDescription.Builder builder = new android.accessibilityservice.GestureDescription.Builder();
        android.graphics.Path path = new android.graphics.Path();
        path.moveTo(x, y);
        builder.addStroke(new android.accessibilityservice.GestureDescription.StrokeDescription(path, 0, 100));
        service.dispatchGesture(builder.build(), null, null);
        Log.d(TAG, "已执行坐标点击: " + x + ", " + y);
    }
    private String getPendingKeyword(Context context) {
        return context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE)
                .getString("pinduoduo_keyword", "").trim();
    }

    private long getPendingRequestId(Context context) {
        return context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE)
                .getLong("pinduoduo_request_id", -1L);
    }
    // 在你的 AccessibilityUtils 或者 Service 中添加这个辅助方法
    public static boolean clickNodeOrParent(AccessibilityNodeInfo node) {
        if (node == null) return false;
        if (node.isClickable()) {
            return node.performAction(AccessibilityNodeInfo.ACTION_CLICK);
        } else {
            // 如果当前节点不可点，尝试点它的父节点
            AccessibilityNodeInfo parent = node.getParent();
            if (parent != null) {
                boolean res = clickNodeOrParent(parent);
                parent.recycle(); // 记得回收
                return res;
            }
        }
        return false;
    }

    private void clearPendingTask(Context context) {
        context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).edit()
                .remove("pinduoduo_keyword")
                .remove("pinduoduo_request_id")
                .apply();
    }
}