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

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

public class PinduoduoAutoService extends AccessibilityService {

    private static final String TAG = "PinduoduoAuto";
    private static final String PINDUODUO_PACKAGE = "com.xunmeng.pinduoduo";

    // 以下 ID 均来自美团 App 布局树，请用 Appium Inspector 或 Layout Inspector 抓取确认后替换
    // ⚠️ 所有 ID 均为推测值，必须替换为真实值后生效

    // 首页相关
    private static final String ID_HOME_SEARCH_ENTRY = "com.xunmeng.pinduoduo:id/search_container";  // 首页搜索入口容器
    private static final String ID_HOME_SEARCH_TXT   = "com.xunmeng.pinduoduo:id/search_hint_text";   // 首页搜索文案 TextView

    // 搜索页相关
    private static final String ID_SEARCH_ET  = "com.xunmeng.pinduoduo:id/search_input_et";            // 搜索页输入框
    private static final String ID_SEARCH_BTN = "com.xunmeng.pinduoduo:id/search_confirm_btn";         // 搜索确认按钮

    // 商品列表页特征文字（用于 STEP_WAIT_RESULT 判断）
    private static final String SEARCH_PLACEHOLDER = "搜索拼多多";  // 搜索页 EditText 占位文案

    // 状态机常量
    private static final int STEP_IDLE              = 0;
    private static final int STEP_CLICK_SEARCH_ENTRY = 1;   // 首页点击搜索入口
    private static final int STEP_INPUT_KEYWORD      = 2;   // 输入搜索关键词
    private static final int STEP_CLICK_SEARCH_BTN  = 3;   // 点击搜索按钮
    private static final int STEP_WAIT_RESULT        = 4;   // 等待商品列表加载

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
        info.packageNames = new String[]{PINDUODUO_PACKAGE};
        info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
                | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        setServiceInfo(info);
        Log.d(TAG, "PinduoduoAutoService 已连接，监听的包名: " + PINDUODUO_PACKAGE);
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        Log.d(TAG, ">>> onAccessibilityEvent 触发: " + event.getEventType() + ", package: " + event.getPackageName());

        if (event == null || event.getPackageName() == null) return;
        if (!PINDUODUO_PACKAGE.contentEquals(event.getPackageName())) return;

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
                Log.d(TAG, "========== 🛒 检测到新拼多多搜索任务：搜「" + targetKeyword + "」==========");

                String windowClass = event.getClassName() != null ? event.getClassName().toString() : "";
                if (isSearchPage(windowClass) || isSearchResultPage(windowClass)) {
                    step = STEP_INPUT_KEYWORD;
                    Log.d(TAG, "已进入搜索页或结果页，跳过首页点击搜索入口");
                } else {
                    step = STEP_CLICK_SEARCH_ENTRY;
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
                || windowClass.contains("PinduoduoSearchActivity");
    }

    private boolean isSearchResultPage(String windowClass) {
        if (windowClass.isEmpty()) return false;
        return windowClass.contains("GoodsSearchResultActivity")
                || windowClass.contains("ProductListActivity")
                || windowClass.contains("ResultActivity");
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
                case STEP_CLICK_SEARCH_ENTRY:
                    if (clickSearchEntry(root)) {
                        Log.d(TAG, "【1】成功点击首页搜索入口");
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
                    } else if (waitForSearchResult(root)) {
                        // 部分版本输入完自动出结果，跳过 STEP_CLICK_SEARCH_BTN
                        Log.d(TAG, "【3】输入后列表已出现，无需再点搜索按钮");
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
        Log.w(TAG, "PinduoduoAutoService 被中断");
    }

    // ---------------------------------
    //         SharedPreferences
    // ---------------------------------
    private String getPendingKeyword() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        return prefs.getString("pinduoduo_keyword", "").trim();
    }

    private long getPendingRequestId() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        return prefs.getLong("pinduoduo_request_id", -1L);
    }

    private void clearPendingTask() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        prefs.edit()
                .remove("pinduoduo_keyword")
                .remove("pinduoduo_request_id")
                .apply();
        Log.d(TAG, "已清理拼多多搜索任务");
    }

    // ---------------------------------
    //         各步骤具体实现
    // ---------------------------------

    /**
     * 步骤1：点击首页搜索入口
     * 拼多多首页通常有一个横向搜索条，点击进入搜索页
     */
    private boolean clickSearchEntry(AccessibilityNodeInfo root) {
        if (clickByViewId(root, ID_HOME_SEARCH_ENTRY)) return true;
        if (clickByViewId(root, ID_HOME_SEARCH_TXT)) return true;
        if (clickByAnyDesc(root, "搜索拼多多", "搜索", "搜索框")) return true;
        if (clickByAnyText(root, "搜索拼多多", "搜索")) return true;
        if (clickSearchBarByViewTree(root)) return true;
        return false;
    }

    /**
     * 步骤2：在搜索页输入框中填入关键词
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
     */
    private boolean clickSearchButton(AccessibilityNodeInfo root) {
        if (clickByViewId(root, ID_SEARCH_BTN)) return true;
        if (clickByAnyText(root, "搜索", "搜索商品")) return true;
        if (clickByAnyDesc(root, "搜索", "确认")) return true;
        // 找键盘上的「搜索」键（输入法弹出后）
        if (clickSearchKeyOnKeyboard(root)) return true;
        return false;
    }

    /**
     * 步骤4：等待商品列表出现
     * 拼多多商品特征：¥符号 / 多人拼团 / 「找相似」/ 商品卡片
     */
    private boolean waitForSearchResult(AccessibilityNodeInfo root) {
        if (nodeExistsByText(root, "¥")) return true;
        if (nodeExistsByText(root, "元")) return true;
        if (nodeExistsByText(root, "找相似")) return true;
        if (nodeExistsByText(root, "单独购买")) return true;
        if (nodeExistsByText(root, "去拼单")) return true;
        if (nodeExistsByText(root, "拼团")) return true;
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
            // 带「搜索拼多多」占位文案的才是搜索输入框
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
     * 首页搜索条遍历：找 LinearLayout/RelativeLayout，内含「搜索拼多多」相关文字即点击
     */
    private boolean clickSearchBarByViewTree(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> all = flatten(root);
        for (AccessibilityNodeInfo node : all) {
            if (node == null) continue;
            CharSequence cls = node.getClassName();
            if (cls == null) continue;
            boolean isLayout = cls.toString().contains("LinearLayout")
                    || cls.toString().contains("RelativeLayout")
                    || cls.toString().contains("FrameLayout");
            if (!isLayout) continue;

            CharSequence tx = node.getText();
            CharSequence cd = node.getContentDescription();
            if (tx != null && (tx.toString().contains("搜索拼多多") || tx.toString().contains("搜索"))) {
                AccessibilityNodeInfo parent = findClickableParent(node);
                if (parent != null && performClick(parent)) return true;
                if (performClick(node)) return true;
            }
            if (cd != null && cd.toString().contains("搜索")) {
                AccessibilityNodeInfo parent = findClickableParent(node);
                if (parent != null && performClick(parent)) return true;
                if (performClick(node)) return true;
            }
        }
        return false;
    }

    /**
     * 输入法键盘上的「搜索」键（有些版本输入完需要点键盘上的搜索）
     * 策略：发 ACTION_SEARCH 按键
     */
    private boolean clickSearchKeyOnKeyboard(AccessibilityNodeInfo root) {
        if (root == null) return false;
        if (root.performAction(5)) {
            Log.d(TAG, "✅ 通过 ACTION_IME_ENTER 触发输入法搜索");
            return true;
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
