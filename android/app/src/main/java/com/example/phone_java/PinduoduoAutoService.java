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
    private static final String ID_HOME_SEARCH_ENTRY = "com.xunmeng.pinduoduo:id/search_container";
    private static final String ID_SEARCH_ET = "com.xunmeng.pinduoduo:id/search_input_et";
    private static final String ID_SEARCH_BTN = "com.xunmeng.pinduoduo:id/search_confirm_btn";

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
                    if (AccessibilityUtils.clickByViewId(root, ID_HOME_SEARCH_ENTRY) || AccessibilityUtils.clickByAnyText(root, "搜索拼多多", "搜索")) {
                        step = STEP_INPUT_KEYWORD;
                        success = true;
                        handler.postDelayed(this, 800);
                        return;
                    }
                    break;
                case STEP_INPUT_KEYWORD:
                    AccessibilityNodeInfo input = AccessibilityUtils.findFirstNodeByViewId(root, ID_SEARCH_ET);
                    if (input == null) input = AccessibilityUtils.findFirstNodeByClass(root, "android.widget.EditText");
                    if (input != null && AccessibilityUtils.inputText(input, targetKeyword)) {
                        step = STEP_CLICK_SEARCH_BTN;
                        success = true;
                        handler.postDelayed(this, 500);
                        return;
                    }
                    break;
                case STEP_CLICK_SEARCH_BTN:
                    if (AccessibilityUtils.clickByViewId(root, ID_SEARCH_BTN) || AccessibilityUtils.clickByAnyText(root, "搜索")) {
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
