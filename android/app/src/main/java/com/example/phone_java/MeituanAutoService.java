package com.example.phone_java;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

public class MeituanAutoService extends AccessibilityService {

    private static final String TAG = "MeituanAuto";
    private static final String MEITUAN_PACKAGE = "com.sankuai.meituan";

    // 以下 ID 均来自美团 App 布局树，请用 Appium Inspector 或 Layout Inspector 抓取确认后替换
    // 首页相关
    private static final String ID_HOME_SEARCH_WRAPPER = "com.sankuai.meituan:id/home_search_wrapper";
    private static final String ID_HOME_SEARCH_TXT     = "com.sankuai.meituan:id/home_search_txt";
    private static final String SEARCH_PLACEHOLDER      = "搜索商家、商品、品类";

    // 搜索页相关
    private static final String ID_SEARCH_ET            = "com.sankuai.meituan:id/search_et";
    private static final String ID_SEARCH_BTN           = "com.sankuai.meituan:id/search_btn";

    // 状态机常量
    private static final int STEP_IDLE                = 0;
    private static final int STEP_CLICK_SEARCH_BOX    = 1;   // 首页点击搜索框
    private static final int STEP_INPUT_KEYWORD     = 2;   // 输入搜索关键词
    private static final int STEP_CLICK_SEARCH_BTN  = 3;   // 点击搜索按钮
    private static final int STEP_WAIT_RESULT        = 4;   // 等待搜索结果加载

    private final Handler handler = new Handler(Looper.getMainLooper());
    private int step = STEP_IDLE;
    private String targetKeyword = "";
    private long lastHandledRequestId = -1L;
    private long stepStartTime = 0L;

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        AccessibilityServiceInfo info = new AccessibilityServiceInfo();
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                | AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED;
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC;
        info.notificationTimeout = 100;
        info.packageNames = new String[]{MEITUAN_PACKAGE};
        info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
                | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        setServiceInfo(info);
        Log.d(TAG, "MeituanAutoService 已连接，监听的包名: " + MEITUAN_PACKAGE);
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        Log.d(TAG, ">>> onAccessibilityEvent 触发: " + event.getEventType() + ", package: " + event.getPackageName());

        if (event == null || event.getPackageName() == null) return;
        if (!MEITUAN_PACKAGE.contentEquals(event.getPackageName())) return;

        long pendingRequestId = getPendingRequestId();
        String pendingKeyword = getPendingKeyword();

        Log.d(TAG, "SharedPreferences 状态:");
        Log.d(TAG, "   - pendingRequestId: " + pendingRequestId);
        Log.d(TAG, "   - pendingKeyword: [" + pendingKeyword + "]");
        Log.d(TAG, "   - lastHandledRequestId: " + lastHandledRequestId);
        Log.d(TAG, "   - 当前 step: " + step);

        if (pendingRequestId > 0 && pendingRequestId != lastHandledRequestId) {
            if (!pendingKeyword.isEmpty()) {
                targetKeyword = pendingKeyword;
                lastHandledRequestId = pendingRequestId;
                stepStartTime = System.currentTimeMillis();
                Log.d(TAG, "========== 🍜 检测到新美团搜索任务：搜「" + targetKeyword + "」==========");

                // 判断是否已进入搜索页（直接进入输入关键词步骤）
                String windowClass = event.getClassName() != null ? event.getClassName().toString() : "";
                if (isSearchPage(windowClass)) {
                    step = STEP_INPUT_KEYWORD;
                    Log.d(TAG, "已进入搜索页，跳过首页点击搜索框");
                } else {
                    step = STEP_CLICK_SEARCH_BOX;
                }
            }
        }

        if (step == STEP_IDLE) return;

        // 超时重置（20秒）
        if (System.currentTimeMillis() - stepStartTime > 20000) {
            Log.e(TAG, "步骤超时卡死，强制重置状态机！当前停留在 step=" + step);
            step = STEP_IDLE;
            clearPendingTask();
            return;
        }

        handler.removeCallbacks(stateMachineRunnable);
        handler.postDelayed(stateMachineRunnable, 600);
    }

    private boolean isSearchPage(String windowClass) {
        if (windowClass.isEmpty()) return false;
        return windowClass.contains("SearchActivity")
                || windowClass.contains("SearchResultActivity")
                || windowClass.contains("MeituanSearchActivity");
    }

    private final Runnable stateMachineRunnable = new Runnable() {
        @Override
        public void run() {
            AccessibilityNodeInfo root = getRootInActiveWindow();
            if (root == null) {
                if (step >= STEP_INPUT_KEYWORD) {
                    handler.removeCallbacks(this);
                    handler.postDelayed(this, 500);
                    return;
                }
                return;
            }

            boolean success = false;

            switch (step) {
                case STEP_CLICK_SEARCH_BOX:
                    if (clickSearchBox(root)) {
                        Log.d(TAG, "【1】成功点击首页搜索框");
                        step = STEP_INPUT_KEYWORD;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                        handler.postDelayed(this, 800);
                        return;
                    }
                    break;

                case STEP_INPUT_KEYWORD:
                    if (inputKeyword(root, targetKeyword)) {
                        Log.d(TAG, "【2】成功在搜索框填入关键词：「" + targetKeyword + "」");
                        step = STEP_CLICK_SEARCH_BTN;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                        handler.postDelayed(this, 500);
                        return;
                    }
                    break;

                case STEP_CLICK_SEARCH_BTN:
                    if (clickSearchButton(root)) {
                        Log.d(TAG, "【3】成功点击搜索按钮，进入商品列表");
                        step = STEP_WAIT_RESULT;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                    }
                    break;

                case STEP_WAIT_RESULT:
                    if (waitForSearchResult(root)) {
                        Log.d(TAG, "【4】商品列表已加载，任务完成！");
                        step = STEP_IDLE;
                        clearPendingTask();
                        success = true;
                    }
                    break;
            }

            if (!success && step != STEP_IDLE) {
                handler.removeCallbacks(this);
                handler.postDelayed(this, 500);
            }
        }
    };

    @Override
    public void onInterrupt() {
        Log.w(TAG, "MeituanAutoService 被中断");
    }

    // ---------------------------------
    //         SharedPreferences
    // ---------------------------------
    private String getPendingKeyword() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        return prefs.getString("meituan_keyword", "").trim();
    }

    private long getPendingRequestId() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        return prefs.getLong("meituan_request_id", -1L);
    }

    private void clearPendingTask() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        prefs.edit()
                .remove("meituan_keyword")
                .remove("meituan_request_id")
                .apply();
        Log.d(TAG, "已清理美团搜索任务");
    }

    // ---------------------------------
    //         各步骤具体实现
    // ---------------------------------

    /**
     * 步骤1：点击首页搜索框
     * 策略1：按 ID 匹配（home_search_wrapper / home_search_txt）
     * 策略2：按 contentDescription 或 text 匹配「���索商家、商品、品类」
     * 策略3：按 text 找搜索入口
     */
    private boolean clickSearchBox(AccessibilityNodeInfo root) {
        if (clickByViewId(root, ID_HOME_SEARCH_WRAPPER)) return true;
        if (clickByViewId(root, ID_HOME_SEARCH_TXT)) return true;
        if (clickByAnyDesc(root, "搜索商家、商品、品类", "搜索", "搜索框")) return true;
        if (clickByAnyText(root, SEARCH_PLACEHOLDER, "搜索")) return true;
        if (clickBySearchBoxByDescOrText(root)) return true;
        return false;
    }

    /**
     * 步骤2：在搜索输入框中填入关键词
     */
    private boolean inputKeyword(AccessibilityNodeInfo root, String keyword) {
        AccessibilityNodeInfo input = findSearchInputEditText(root);
        if (input == null) {
            input = findFirstNodeByClass(root, "android.widget.EditText");
        }
        if (input == null) return false;

        input.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
        Bundle args = new Bundle();
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, keyword);
        boolean ok = input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
        if (ok) {
            Log.d(TAG, "✅ 已填入搜索关键词: " + keyword);
        }
        return ok;
    }

    /**
     * 步骤3：点击搜索按钮
     * 美团搜索按钮通常是「搜索」TextView 或 Button
     */
    private boolean clickSearchButton(AccessibilityNodeInfo root) {
        if (clickByViewId(root, ID_SEARCH_BTN)) return true;
        if (clickByAnyText(root, "搜索", "查找")) return true;
        if (clickByAnyDesc(root, "搜索")) return true;
        return false;
    }

    /**
     * 步骤4：等待商品列表出现
     * 检测到美团商品特征（¥价格符号 / 「找相似」/ 结果卡片等）即认为加载完成
     */
    private boolean waitForSearchResult(AccessibilityNodeInfo root) {
        if (nodeExistsByText(root, "¥")) return true;
        if (nodeExistsByText(root, "元")) return true;
        if (nodeExistsByText(root, "找相似")) return true;
        if (nodeExistsByText(root, "立即预订")) return true;
        return false;
    }

    /**
     * 优先找搜索页顶部的 EditText（带占位文案）
     */
    private AccessibilityNodeInfo findSearchInputEditText(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> all = flatten(root);
        for (AccessibilityNodeInfo node : all) {
            if (node == null) continue;
            CharSequence cls = node.getClassName();
            if (cls == null || !"android.widget.EditText".contentEquals(cls)) continue;
            CharSequence tx = node.getText();
            if (tx != null && (tx.toString().contains(SEARCH_PLACEHOLDER) || tx.toString().contains("搜索"))) {
                return node;
            }
        }
        AccessibilityNodeInfo first = findFirstNodeByViewId(root, ID_SEARCH_ET);
        if (first != null) return first;
        return null;
    }

    private boolean nodeExistsByText(AccessibilityNodeInfo root, String text) {
        List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByText(text);
        return nodes != null && !nodes.isEmpty();
    }

    /**
     * 首页找搜索框：遍历整棵树，找 TextView 或 LinearLayout，text / content-desc / className 任一匹配即点击
     */
    private boolean clickBySearchBoxByDescOrText(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> all = flatten(root);
        for (AccessibilityNodeInfo node : all) {
            if (node == null) continue;
            boolean matched = false;
            CharSequence tx = node.getText();
            CharSequence cd = node.getContentDescription();
            CharSequence cls = node.getClassName();
            if (cls != null && cls.toString().contains("LinearLayout")) {
                if (tx != null && (tx.toString().contains("搜索商家") || tx.toString().contains("搜索"))) matched = true;
                if (cd != null && cd.toString().contains("搜索")) matched = true;
            }
            if (cls != null && cls.toString().contains("TextView")) {
                if (tx != null && (tx.toString().contains("搜索商家") || tx.toString().contains("搜索"))) matched = true;
            }
            if (matched) {
                AccessibilityNodeInfo parent = findClickableParent(node);
                if (parent != null && performClick(parent)) return true;
                if (performClick(node)) return true;
            }
        }
        return false;
    }

    // ---------------------------------
    //         底层通用工具方法
    // ---------------------------------

    private boolean clickByAnyText(AccessibilityNodeInfo root, String... texts) {
        List<AccessibilityNodeInfo> nodes = findNodesByAnyText(root, texts);
        for (AccessibilityNodeInfo node : nodes) {
            if (performClick(node)) return true;
        }
        return false;
    }

    private boolean clickByAnyDesc(AccessibilityNodeInfo root, String... descs) {
        List<AccessibilityNodeInfo> all = flatten(root);
        for (AccessibilityNodeInfo node : all) {
            if (node == null) continue;
            CharSequence cd = node.getContentDescription();
            if (cd == null) continue;
            String value = cd.toString();
            for (String d : descs) {
                if (d != null && !d.isEmpty() && value.contains(d)) {
                    if (performClick(node)) return true;
                }
            }
        }
        return false;
    }

    private boolean clickByViewId(AccessibilityNodeInfo root, String viewId) {
        if (viewId == null || viewId.isEmpty()) return false;
        List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByViewId(viewId);
        if (nodes == null || nodes.isEmpty()) return false;
        for (AccessibilityNodeInfo node : nodes) {
            if (performClick(node)) return true;
        }
        return false;
    }

    private boolean performClick(AccessibilityNodeInfo node) {
        AccessibilityNodeInfo cur = node;
        while (cur != null) {
            if (cur.isClickable()) {
                return cur.performAction(AccessibilityNodeInfo.ACTION_CLICK);
            }
            cur = cur.getParent();
        }
        return false;
    }

    private AccessibilityNodeInfo findClickableParent(AccessibilityNodeInfo node) {
        if (node == null) return null;
        AccessibilityNodeInfo cur = node.getParent();
        while (cur != null) {
            if (cur.isClickable()) return cur;
            cur = cur.getParent();
        }
        return null;
    }

    private List<AccessibilityNodeInfo> findNodesByAnyText(AccessibilityNodeInfo root, String... texts) {
        List<AccessibilityNodeInfo> result = new ArrayList<>();
        if (root == null) return result;
        for (String text : texts) {
            if (text == null || text.trim().isEmpty()) continue;
            List<AccessibilityNodeInfo> found = root.findAccessibilityNodeInfosByText(text);
            if (found != null && !found.isEmpty()) result.addAll(found);
        }
        return result;
    }

    private AccessibilityNodeInfo findFirstNodeByViewId(AccessibilityNodeInfo root, String viewId) {
        if (viewId == null || viewId.isEmpty()) return null;
        List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByViewId(viewId);
        return (nodes != null && !nodes.isEmpty()) ? nodes.get(0) : null;
    }

    private AccessibilityNodeInfo findFirstNodeByClass(AccessibilityNodeInfo root, String className) {
        if (root == null) return null;
        Deque<AccessibilityNodeInfo> queue = new ArrayDeque<>();
        queue.add(root);
        while (!queue.isEmpty()) {
            AccessibilityNodeInfo node = queue.poll();
            if (node == null) continue;
            CharSequence cls = node.getClassName();
            if (cls != null && className.contentEquals(cls)) return node;
            for (int i = 0; i < node.getChildCount(); i++) {
                AccessibilityNodeInfo child = node.getChild(i);
                if (child != null) queue.add(child);
            }
        }
        return null;
    }

    private List<AccessibilityNodeInfo> flatten(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> out = new ArrayList<>();
        if (root == null) return out;
        Deque<AccessibilityNodeInfo> queue = new ArrayDeque<>();
        queue.add(root);
        while (!queue.isEmpty()) {
            AccessibilityNodeInfo node = queue.poll();
            if (node == null) continue;
            out.add(node);
            for (int i = 0; i < node.getChildCount(); i++) {
                AccessibilityNodeInfo child = node.getChild(i);
                if (child != null) queue.add(child);
            }
        }
        return out;
    }
}
