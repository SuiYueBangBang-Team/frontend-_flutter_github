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

public class AmapAutoService extends AccessibilityService {

    private static final String TAG = "AmapAuto";
    private static final String AMAP_PACKAGE = "com.autonavi.minimap";

    // 【修复】修正首页搜索框ID（maphome而非maphone）
    // 兼容旧版或备用 ID
    private static final String ID_SEARCH_BTN_LEGACY = "com.autonavi.minimap:id/search_btn"; // <-- 加这行
    private static final String ID_HOME_SEARCHBAR_BG = "com.autonavi.minimap:id/maphome_searchbar_bg";
    private static final String ID_HOME_SEARCHBAR_CONTAINER = "com.autonavi.minimap:id/maphome_searchbar_container";
    private static final String ID_HOME_TXT_HOTWORD = "com.autonavi.minimap:id/txt_hotword";
    private static final String ID_HOME_SCAN_BTN = "com.autonavi.minimap:id/btn_qrscan";
    private static final String ID_HOME_VOICE_BTN = "com.autonavi.minimap:id/btn_voice";

    // 【新增】搜索页/结果页关键ID（适配多版本）
    private static final String ID_SEARCH_INPUT = "com.autonavi.minimap:id/input_search";
    private static final String ID_SEARCH_BTN = "com.autonavi.minimap:id/btn_search";
    private static final String ID_RESULT_ITEM_CONTAINER = "com.autonavi.minimap:id/widget_item_container";
    private static final String ID_NAVI_BTN = "com.autonavi.minimap:id/btn_navi";

    private static final String SEARCH_PLACEHOLDER = "查找地点、公交、地铁";
    private static final String SEARCH_PLACEHOLDER_ALT = "搜索地点、公交、地铁";

    // 状态机常量
    private static final int STEP_IDLE                = 0;
    private static final int STEP_CLICK_SEARCH_BOX    = 1;
    private static final int STEP_INPUT_DESTINATION   = 2;
    private static final int STEP_CLICK_SEARCH_BTN    = 3;
    private static final int STEP_CLICK_RESULT_ITEM   = 4;
    private static final int STEP_CLICK_GO_HERE      = 5;
    private static final int STEP_CONFIRM_NAVI        = 6;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private int step = STEP_IDLE;
    private String targetDestination = "";
    private long lastHandledRequestId = -1L;
    private long stepStartTime = 0L;
    private static final long STEP_TIMEOUT = 15000; // 分步骤超时15秒

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        AccessibilityServiceInfo info = new AccessibilityServiceInfo();
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                | AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
                | AccessibilityEvent.TYPE_VIEW_CLICKED
                | AccessibilityEvent.TYPE_VIEW_FOCUSED; // 补充焦点事件
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC;
        info.notificationTimeout = 100;
        info.packageNames = new String[]{AMAP_PACKAGE};
        info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
                | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        setServiceInfo(info);
        Log.d(TAG, "AmapAutoService 已连接，监听的包名: " + AMAP_PACKAGE);
        Log.d(TAG, "✅ 已修正搜索框ID: " + ID_HOME_SEARCHBAR_BG);
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        Log.d(TAG, ">>> onAccessibilityEvent 触发: " + event.getEventType() + ", package: " + event.getPackageName());

        if (event == null || event.getPackageName() == null) return;
        if (!AMAP_PACKAGE.contentEquals(event.getPackageName())) return;

        long pendingRequestId = getPendingRequestId();
        String pendingDestination = getPendingDestination();

        Log.d(TAG, "SharedPreferences 状态:");
        Log.d(TAG, "   - pendingRequestId: " + pendingRequestId);
        Log.d(TAG, "   - pendingDestination: [" + pendingDestination + "]");
        Log.d(TAG, "   - lastHandledRequestId: " + lastHandledRequestId);
        Log.d(TAG, "   - 当前 step: " + step);

        // 检测到新任务，启动状态机
        if (pendingRequestId > 0 && pendingRequestId != lastHandledRequestId) {
            if (!pendingDestination.isEmpty()) {
                targetDestination = pendingDestination;
                lastHandledRequestId = pendingRequestId;
                stepStartTime = System.currentTimeMillis();
                Log.d(TAG, "========== 🗺️ 检测到新导航任务：去 " + targetDestination + " ==========");

                // 【优化】双重判断：节点特征+Activity类名
                AccessibilityNodeInfo rootProbe = getRootInActiveWindow();
                try {
                    boolean isInSearchFlow = false;
                    if (rootProbe != null) {
                        AccessibilityNodeInfo input = findSearchPageEditText(rootProbe);
                        isInSearchFlow = input != null;
                    }

                    String windowClass = event.getClassName() != null ? event.getClassName().toString() : "";
                    if (isInSearchFlow || isSearchPage(windowClass) || isSearchResultPage(windowClass)) {
                        step = STEP_INPUT_DESTINATION;
                        Log.d(TAG, "✅ 已在搜索流程中，跳过首页点击搜索条");
                    } else {
                        step = STEP_CLICK_SEARCH_BOX;
                        Log.d(TAG, "✅ 进入首页点击搜索框步骤");
                    }
                } finally {
                    if (rootProbe != null) {
                        rootProbe.recycle(); // 【修复】确保节点回收
                    }
                }
            } else {
                Log.w(TAG, "⚠️ 任务ID有效，但目的地为空，不启动流程");
            }
        }

        if (step == STEP_IDLE) return;

        // 【优化】分步骤超时
        if (System.currentTimeMillis() - stepStartTime > STEP_TIMEOUT) {
            Log.e(TAG, "❌ 步骤超时卡死，强制重置状态机！当前停留在 step=" + step);
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
                || windowClass.contains("KeywordSearchActivity")
                || windowClass.contains("SearchPoiActivity")
                || windowClass.contains("InputSearchActivity")
                || windowClass.contains("SearchMainActivity"); // 补充多版本Activity
    }

    private boolean isSearchResultPage(String windowClass) {
        if (windowClass.isEmpty()) return false;
        return windowClass.contains("ResultActivity")
                || windowClass.contains("PoiResultActivity")
                || windowClass.contains("SearchResultActivity")
                || windowClass.contains("PoiListActivity")
                || windowClass.contains("PoiDetailActivity"); // 补充详情页
    }

    private final Runnable stateMachineRunnable = new Runnable() {
        @Override
        public void run() {
            AccessibilityNodeInfo root = getRootInActiveWindow();
            if (root == null) {
                Log.w(TAG, "⚠️ 获取根节点失败，重试...");
                handler.removeCallbacks(this);
                handler.postDelayed(this, 500);
                return;
            }

            boolean success = false;

            switch (step) {
                case STEP_CLICK_SEARCH_BOX:
                    Log.d(TAG, "🔍 执行步骤1：点击首页搜索框");
                    if (clickSearchBox(root)) {
                        Log.d(TAG, "✅ 步骤1成功：点击搜索框");
                        step = STEP_INPUT_DESTINATION;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                        handler.postDelayed(this, 1000); // 【优化】延长跳转时间，适配输入法弹出
                        return;
                    } else {
                        Log.e(TAG, "❌ 步骤1失败：未找到可点击的搜索框");
                    }
                    break;

                case STEP_INPUT_DESTINATION:
                    Log.d(TAG, "🔍 执行步骤2：输入目的地: " + targetDestination);
                    if (inputDestination(root, targetDestination)) {
                        Log.d(TAG, "✅ 步骤2成功：填入目的地");
                        step = STEP_CLICK_SEARCH_BTN;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                        handler.postDelayed(this, 800); // 等待联想结果
                        return;
                    } else {
                        Log.e(TAG, "❌ 步骤2失败：未找到输入框或输入失败");
                    }
                    break;

                case STEP_CLICK_SEARCH_BTN:
                    Log.d(TAG, "🔍 执行步骤3：点击搜索按钮");
                    if (clickSearchButton(root)) {
                        Log.d(TAG, "✅ 步骤3成功：点击搜索按钮");
                        step = STEP_CLICK_RESULT_ITEM;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                        handler.postDelayed(this, 1000); // 等待结果加载
                    } else if (clickResultRowByDestination(root, targetDestination)) {
                        Log.d(TAG, "✅ 步骤3兜底：直接匹配到结果列表项，跳过搜索按钮");
                        step = STEP_CLICK_GO_HERE;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                    } else {
                        Log.e(TAG, "❌ 步骤3失败：未找到搜索按钮或结果项");
                    }
                    break;

                case STEP_CLICK_RESULT_ITEM:
                    Log.d(TAG, "🔍 执行步骤4：点击搜索结果");
                    if (clickFirstResult(root, targetDestination)) {
                        Log.d(TAG, "✅ 步骤4成功：点击搜索结果，进入详情页");
                        step = STEP_CLICK_GO_HERE;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                        handler.postDelayed(this, 1000); // 等待详情页加载
                    } else {
                        Log.e(TAG, "❌ 步骤4失败：未找到匹配的结果项");
                    }
                    break;

                case STEP_CLICK_GO_HERE:
                    Log.d(TAG, "🔍 执行步骤5：点击导航按钮");
                    if (clickGoHereButton(root)) {
                        Log.d(TAG, "✅ 步骤5成功：点击「导航」按钮");
                        step = STEP_CONFIRM_NAVI;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                        handler.postDelayed(this, 800);
                    } else {
                        Log.e(TAG, "❌ 步骤5失败：未找到导航按钮");
                    }
                    break;

                case STEP_CONFIRM_NAVI:
                    Log.d(TAG, "🔍 执行步骤6：确认导航");
                    if (confirmNavigation(root)) {
                        Log.d(TAG, "✅ 步骤6成功：导航任务完成！");
                        step = STEP_IDLE;
                        clearPendingTask();
                        success = true;
                    } else {
                        Log.e(TAG, "❌ 步骤6失败：未进入导航界面");
                    }
                    break;
            }

            if (!success && step != STEP_IDLE) {
                handler.removeCallbacks(this);
                handler.postDelayed(this, 500);
            }

            root.recycle(); // 【修复】根节点回收
        }
    };

    @Override
    public void onInterrupt() {
        Log.w(TAG, "AmapAutoService 被中断");
        handler.removeCallbacks(stateMachineRunnable);
        step = STEP_IDLE;
    }

    // ---------------------------------
    //         SharedPreferences
    // ---------------------------------
    private String getPendingDestination() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        return prefs.getString("amap_destination", "").trim();
    }

    private long getPendingRequestId() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        return prefs.getLong("amap_request_id", -1L);
    }

    private void clearPendingTask() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        prefs.edit()
                .remove("amap_destination")
                .remove("amap_request_id")
                .apply();
        Log.d(TAG, "✅ 已清理高德导航任务");
    }

    // ---------------------------------
    //         各步骤具体实现
    // ---------------------------------

    /**
     * 步骤1：点击首页搜索条（多ID+多特征兜底）
     */
    private boolean clickSearchBox(AccessibilityNodeInfo root) {
        if (clickByViewId(root, ID_HOME_SEARCHBAR_BG)) return true;
        if (clickByViewId(root, ID_HOME_SEARCHBAR_CONTAINER)) return true;
        if (clickByViewId(root, ID_HOME_TXT_HOTWORD)) return true;
        if (clickByAnyDesc(root, "搜索框", "查找地点", "公交", "地铁")) return true;
        if (clickByAnyText(root, SEARCH_PLACEHOLDER, SEARCH_PLACEHOLDER_ALT)) return true;
        // 【新增】兜底：点击搜索框附近的可点击区域
        AccessibilityNodeInfo scanBtn = findFirstNodeByViewId(root, ID_HOME_SCAN_BTN);
        if (scanBtn != null) {
            AccessibilityNodeInfo parent = scanBtn.getParent();
            if (parent != null && performClick(parent)) {
                Log.d(TAG, "✅ 通过扫码按钮父节点点击搜索框");
                return true;
            }
        }
        return false;
    }

    /**
     * 步骤2：在搜索页顶部 EditText 输入目的地（多ID+占位符兜底）
     */
    /**
     * 步骤2：在搜索页顶部 EditText 输入目的地（多ID+占位符兜底）
     */
    private boolean inputDestination(AccessibilityNodeInfo root, String destination) {
        AccessibilityNodeInfo input = findFirstNodeByViewId(root, ID_SEARCH_INPUT);
        if (input == null) {
            Log.w(TAG, "⚠️ 未找到ID对应的输入框，尝试找带占位符的EditText");
            input = findSearchPageEditText(root);
        }
        if (input == null) {
            Log.w(TAG, "⚠️ 未找到带占位符的输入框，尝试找第一个EditText兜底");
            input = findFirstNodeByClass(root, "android.widget.EditText");
        }
        if (input == null) {
            Log.e(TAG, "❌ 完全找不到输入框，输入失败");
            return false;
        }

        try {
            // 【修复】简化输入逻辑，解决输入失败问题
            boolean ok = false;

            // 方法1：直接设置文本（最稳定）
            Bundle args = new Bundle();
            args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, destination);
            ok = input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);

            // 方法2：如果失败，尝试先聚焦再输入
            if (!ok) {
                input.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
                ok = input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
            }

            if (ok) {
                Log.d(TAG, "✅ 已成功填入目的地: " + destination);
            } else {
                Log.e(TAG, "❌ 输入框赋值失败");
            }
            return ok;

        } catch (Exception e) {
            Log.e(TAG, "❌ 输入异常: " + e.getMessage());
            return false;
        }
    }
    /**
     * 步骤3：点击搜索页右上角「搜索」按钮（多ID+文字兜底）
     */
    private boolean clickSearchButton(AccessibilityNodeInfo root) {
        if (clickByViewId(root, ID_SEARCH_BTN)) return true;
        if (clickByViewId(root, ID_SEARCH_BTN_LEGACY)) return true;
        if (clickByAnyText(root, "搜索")) return true;
        if (clickByAnyDesc(root, "搜索")) return true;
        return false;
    }

    /**
     * 步骤4：点击列表里对应地址（优化匹配逻辑，跳过广告）
     */
    private boolean clickFirstResult(AccessibilityNodeInfo root, String destination) {
        if (clickResultRowByDestination(root, destination)) return true;
        if (clickByAnyTextWithParentClickSkipEditText(root, destination)) return true;

        String[] keywords = splitKeywords(destination);
        for (String keyword : keywords) {
            if (keyword.length() >= 2 && clickByAnyTextWithParentClickSkipEditText(root, keyword)) {
                Log.d(TAG, "✅ 通过关键词「" + keyword + "」点击了结果项");
                return true;
            }
        }

        if (clickFirstResultItem(root)) return true;
        return clickFirstResultInAllWindows(destination);
    }

    /**
     * 步骤5：POI 详情底栏点击「导航」（优先ID+位置匹配）
     */
    private boolean clickGoHereButton(AccessibilityNodeInfo root) {
        if (clickByViewId(root, ID_NAVI_BTN)) return true;
        if (clickNavigateTextButton(root)) return true;
        if (clickByAnyText(root, "开始导航", "到这里去", "导航去")) return true;
        if (clickByAnyDesc(root, "导航", "开始导航")) return true;
        return false;
    }

    /**
     * 步骤6：二次确认或检测已进入导航
     */
    private boolean confirmNavigation(AccessibilityNodeInfo root) {
        if (isInNavigationMode(root)) {
            Log.d(TAG, "✅ 已检测到导航界面特征，任务完成");
            return true;
        }
        if (clickByAnyText(root, "开始导航", "确定", "确认", "开始")) return true;
        if (clickByAnyDesc(root, "开始导航")) return true;
        return false;
    }

    /** 搜索页：优先找带占位文案的 EditText */
    private AccessibilityNodeInfo findSearchPageEditText(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> all = flatten(root);
        for (AccessibilityNodeInfo node : all) {
            if (node == null) continue;
            CharSequence cls = node.getClassName();
            if (cls == null || !"android.widget.EditText".contentEquals(cls)) continue;
            CharSequence tx = node.getText();
            if (tx != null && (tx.toString().contains(SEARCH_PLACEHOLDER) || tx.toString().contains(SEARCH_PLACEHOLDER_ALT))) {
                Log.d(TAG, "✅ 找到带占位符的搜索输入框");
                return node;
            }
        }
        return null;
    }

    /** 按 content-desc 匹配 POI 名称点击整行（处理富文本） */
    private boolean clickResultRowByDestination(AccessibilityNodeInfo root, String destination) {
        if (destination == null || destination.trim().isEmpty()) return false;
        String key = normalizeUiText(destination.trim());
        List<AccessibilityNodeInfo> all = flatten(root);
        for (AccessibilityNodeInfo node : all) {
            if (node == null) continue;
            // 【优化】同时匹配content-desc和text
            CharSequence cd = node.getContentDescription();
            CharSequence tx = node.getText();
            String d = "";
            if (cd != null) d = normalizeUiText(cd.toString().trim());
            else if (tx != null) d = normalizeUiText(tx.toString().trim());
            if (d.isEmpty()) continue;

            if (d.equals(key) || d.contains(key) || key.contains(d)) {
                // 跳过广告
                if (d.contains("广告") || d.contains("推广")) continue;
                if (performClick(node)) {
                    Log.d(TAG, "✅ 通过 content-desc/text 点击结果行: " + d);
                    return true;
                }
                AccessibilityNodeInfo parent = findClickableParent(node);
                if (parent != null && performClick(parent)) {
                    Log.d(TAG, "✅ 通过父节点点击结果行: " + d);
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * 详情页底部「导航」：优先从树末尾向前找 text 精确为「导航」的节点（过滤非按钮）
     */
    private boolean clickNavigateTextButton(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> all = flatten(root);
        // 倒序查找，优先底部按钮
        for (int i = all.size() - 1; i >= 0; i--) {
            AccessibilityNodeInfo node = all.get(i);
            if (node == null) continue;
            CharSequence t = node.getText();
            if (t == null) continue;
            String text = normalizeUiText(t.toString());
            if ("导航".equals(text)) {
                // 【优化】确保是可点击按钮
                if (node.isClickable() && performClick(node)) {
                    Log.d(TAG, "✅ 已点击底栏「导航」按钮");
                    return true;
                }
                AccessibilityNodeInfo parent = findClickableParent(node);
                if (parent != null && performClick(parent)) {
                    Log.d(TAG, "✅ 已通过父节点点击「导航」按钮");
                    return true;
                }
            }
        }
        return false;
    }

    private static String normalizeUiText(String raw) {
        if (raw == null) return "";
        String s = raw.trim();
        // 【优化】更彻底的富文本过滤
        if (s.contains("<") && s.contains(">")) {
            s = s.replaceAll("<[^>]+>", "");
        }
        // 去除特殊符号
        s = s.replaceAll("[&;@#\\\"']", "");
        return s.trim();
    }

    /** 点击含指定文字的节点时跳过仍在搜索框内的 EditText，避免误点输入框 */
    private boolean clickByAnyTextWithParentClickSkipEditText(AccessibilityNodeInfo root, String... texts) {
        List<AccessibilityNodeInfo> nodes = findNodesByAnyText(root, texts);
        for (AccessibilityNodeInfo node : nodes) {
            if (node == null) continue;
            if (isUnderSearchEditText(node)) continue;
            CharSequence cls = node.getClassName();
            if (cls != null && cls.toString().contains("EditText")) continue;
            // 跳过广告
            CharSequence tx = node.getText();
            if (tx != null && (tx.toString().contains("广告") || tx.toString().contains("推广"))) continue;

            AccessibilityNodeInfo clickable = findClickableParent(node);
            if (clickable != null && performClick(clickable)) {
                Log.d(TAG, "✅ 通过文字匹配点击了列表项（跳过搜索框）");
                return true;
            }
            if (performClick(node)) return true;
        }
        return false;
    }

    private boolean isUnderSearchEditText(AccessibilityNodeInfo node) {
        AccessibilityNodeInfo cur = node;
        int depth = 0;
        while (cur != null && depth++ < 24) {
            CharSequence cls = cur.getClassName();
            if (cls != null && "android.widget.EditText".contentEquals(cls)) {
                CharSequence tx = cur.getText();
                if (tx != null && (tx.toString().contains(SEARCH_PLACEHOLDER) || tx.toString().contains(SEARCH_PLACEHOLDER_ALT))) {
                    return true;
                }
            }
            cur = cur.getParent();
        }
        return false;
    }

    private boolean isInNavigationMode(AccessibilityNodeInfo root) {
        if (nodeExistsByText(root, "剩余")) return true;
        if (nodeExistsByText(root, "公里")) return true;
        if (nodeExistsByText(root, "米")) return true;
        if (nodeExistsByText(root, "导航中")) return true;
        if (nodeExistsByDesc(root, "导航")) return true;
        if (nodeExistsByText(root, "路线")) return true;
        if (nodeExistsByText(root, "前方")) return true;
        if (nodeExistsByText(root, "预计到达")) return true;
        return false;
    }

    private boolean nodeExistsByText(AccessibilityNodeInfo root, String text) {
        List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByText(text);
        return nodes != null && !nodes.isEmpty();
    }

    private boolean nodeExistsByDesc(AccessibilityNodeInfo root, String desc) {
        List<AccessibilityNodeInfo> all = flatten(root);
        for (AccessibilityNodeInfo node : all) {
            CharSequence cd = node.getContentDescription();
            if (cd != null && cd.toString().contains(desc)) return true;
        }
        return false;
    }

    // ---------------------------------
    //         底层通用工具方法
    // ---------------------------------

    /**
     * 点击第一个列表结果项（广告除外）
     */
    private boolean clickFirstResultItem(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> all = flatten(root);
        for (AccessibilityNodeInfo node : all) {
            CharSequence text = node.getText();
            if (text == null) continue;
            String t = normalizeUiText(text.toString());
            // 跳过广告/过短文字
            if (t.contains("广告") || t.contains("推广") || t.trim().length() < 2) continue;

            AccessibilityNodeInfo clickable = findClickableParent(node);
            if (clickable != null && performClick(clickable)) {
                Log.d(TAG, "✅ 点击了第一个结果项: " + t);
                return true;
            }
        }
        return false;
    }

    private boolean clickFirstResultInAllWindows(String destination) {
        List<AccessibilityWindowInfo> windows = getWindows();
        if (windows == null) return false;
        for (AccessibilityWindowInfo window : windows) {
            AccessibilityNodeInfo windowRoot = window.getRoot();
            if (windowRoot == null) continue;
            try {
                if (destination != null && !destination.isEmpty() && clickResultRowByDestination(windowRoot, destination)) {
                    return true;
                }
                if (clickFirstResultItem(windowRoot)) return true;
            } finally {
                windowRoot.recycle(); // 【修复】窗口根节点回收
            }
        }
        return false;
    }

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
        if (nodes == null || nodes.isEmpty()) {
            Log.w(TAG, "⚠️ 未找到ID对应的节点: " + viewId);
            return false;
        }
        for (AccessibilityNodeInfo node : nodes) {
            if (performClick(node)) {
                Log.d(TAG, "✅ 通过ID点击成功: " + viewId);
                return true;
            }
        }
        return false;
    }

    private boolean performClick(AccessibilityNodeInfo node) {
        if (node == null) return false;
        AccessibilityNodeInfo cur = node;
        while (cur != null) {
            if (cur.isClickable()) {
                boolean result = cur.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                Log.d(TAG, "🔘 执行点击: " + cur.getClassName() + ", 结果: " + result);
                return result;
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
        if (nodes != null && !nodes.isEmpty()) {
            return nodes.get(0);
        }
        return null;
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

    /**
     * 将目的地字符串拆分为关键词列表
     */
    private String[] splitKeywords(String destination) {
        List<String> parts = new ArrayList<>();
        parts.add(destination);
        String[] splits = destination.split("[\\s,，。#]");
        for (String s : splits) {
            s = s.trim();
            if (s.length() >= 2) parts.add(s);
        }
        parts.sort((a, b) -> b.length() - a.length());
        return parts.toArray(new String[0]);
    }
}