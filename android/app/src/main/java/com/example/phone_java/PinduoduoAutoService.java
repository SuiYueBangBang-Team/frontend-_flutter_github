package com.example.phone_java;

import android.accessibilityservice.AccessibilityService;
import android.content.Context;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

/**
 * 拼多多自动化处理器 - 由 UnifiedAccessibilityService 调度
 */
public class PinduoduoAutoService {

    private static final String TAG = "PinduoduoAuto";
    // 📷 以下节点 ID 均通过 UIAutomatorViewer 在真机上抓取确认（见项目自动化.md 图片记录）
    // 图男2：搜索入口容器 LinearLayout resource-id="com.xunmeng.pinduoduo:id/pdf"
    // 图男3：搜索页 EditText content-desc="搜索"、搜索按钮 TextView text="搜索"
    //          resource-id="com.xunmeng.pinduoduo:id/pdf" (same namespace, search_input EditText)
    private static final String ID_HOME_SEARCH_ENTRY = "com.xunmeng.pinduoduo:id/pdf";   // 首页搜索入口
    private static final String ID_SEARCH_ET = "com.xunmeng.pinduoduo:id/pdf";           // 搜索页输入框（内部的 EditText）
    private static final String ID_SEARCH_BTN = "com.xunmeng.pinduoduo:id/pdf";         // 搜索按钮（用文字匹配作为主要策略）

    private static final int STEP_IDLE              = 0;
    private static final int STEP_CLICK_SEARCH_ENTRY = 1;
    private static final int STEP_INPUT_KEYWORD      = 2;
    private static final int STEP_CLICK_SEARCH_BTN  = 3;

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
                step = STEP_CLICK_SEARCH_ENTRY;
                Log.d(TAG, "========== 🛒 拼多多动作：搜「" + targetKeyword + "」==========");
            }
        }

        if (step == STEP_IDLE) return;

        if (System.currentTimeMillis() - stepStartTime > 20000) {
            Log.e(TAG, "超时卡死，重置");
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

            boolean success = false;
            switch (step) {
                case STEP_CLICK_SEARCH_ENTRY:
                    // 策略1：点击 ID（图男2 抓取：resource-id="com.xunmeng.pinduoduo:id/pdf"）
                    // 策略2：按文字匹配搜索入口
                    // 策略3：按 content-description 匹配
                    if (AccessibilityUtils.clickByViewId(root, ID_HOME_SEARCH_ENTRY)
                            || AccessibilityUtils.clickByAnyText(root, "搜索拼多多", "搜索")
                            || AccessibilityUtils.clickByAnyDesc(root, "搜索拼多多", "搜索")) {
                        step = STEP_INPUT_KEYWORD;
                        success = true;
                        handler.postDelayed(this, 800); // 等待搜索页加载
                        return;
                    }
                    break;
                case STEP_INPUT_KEYWORD:
                    // 策略1：精确 ID 匹配输入框
                    // 策略2：页面内第一个 EditText（字符串匹配 class 名）
                    AccessibilityNodeInfo input = AccessibilityUtils.findFirstNodeByViewId(root, ID_SEARCH_ET);
                    if (input == null) input = AccessibilityUtils.findFirstNodeByClass(root, "android.widget.EditText");
                    if (input != null && AccessibilityUtils.inputText(input, targetKeyword)) {
                        step = STEP_CLICK_SEARCH_BTN;
                        success = true;
                        handler.postDelayed(this, 600);
                        return;
                    }
                    break;
                case STEP_CLICK_SEARCH_BTN:
                    // 策略1：点击 搜索按钮（图男3 抓取：text="搜索"，resource-id属 com.xunmeng.pinduoduo:id/pdf）
                    // 策略2：按文字匹配「搜索」
                    if (AccessibilityUtils.clickByAnyText(root, "搜索")
                            || AccessibilityUtils.clickByViewId(root, ID_SEARCH_BTN)) {
                        step = STEP_IDLE;
                        clearPendingTask(serviceInstance);
                        success = true;
                    }
                    break;
            }

            if (!success && step != STEP_IDLE) {
                handler.postDelayed(this, 500);
            }
        }
    };

    private String getPendingKeyword(Context context) {
        return context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).getString("pinduoduo_keyword", "").trim();
    }
    private long getPendingRequestId(Context context) {
        return context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).getLong("pinduoduo_request_id", -1L);
    }
    private void clearPendingTask(Context context) {
        context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).edit().remove("pinduoduo_keyword").remove("pinduoduo_request_id").apply();
    }
}
