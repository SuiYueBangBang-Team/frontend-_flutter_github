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

    // 以下 ID 来自真机 Appium Inspector / 布局树（高德地图首页、搜索页、结果列表、POI 详情）
    // 若 App 大版本升级导致失效，请重新抓取后替换。

    /** 首页：搜索条紫色背景容器（LinearLayout），点击后进入搜索页 ✅ 修正ID：maphone 而非 naphome */
    private static final String ID_HOME_SEARCHBAR_BG = "com.autonavi.minimap:id/maphone_searchbar_bg";
    /** 首页：搜索条外层容器 */
    private static final String ID_HOME_SEARCHBAR_CONTAINER = "com.autonavi.minimap:id/maphone_searchbar_container";
    /** 首页：热搜词 TextView「查找地点、公交、地铁」 */
    private static final String ID_HOME_TXT_HOTWORD = "com.autonavi.minimap:id/txt_hotword";

    /** 搜索页占位/提示文案（与截图 EditText 上 text 一致） */
    private static final String SEARCH_PLACEHOLDER = "查找地点、公交、地铁";

    // 兼容旧版或备用 ID（保留作兜底）
    private static final String ID_SEARCH_BTN_LEGACY = "com.autonavi.minimap:id/search_btn";

    // 状态机常量
    private static final int STEP_IDLE                = 0;
    private static final int STEP_CLICK_SEARCH_BOX    = 1;   // 首页点击搜索框
    private static final int STEP_INPUT_DESTINATION   = 2;   // 输入目的地
    private static final int STEP_CLICK_SEARCH_BTN    = 3;   // 点击搜索按钮
    private static final int STEP_CLICK_RESULT_ITEM   = 4;   // 点击搜索结果
    private static final int STEP_CLICK_GO_HERE      = 5;   // 点击"到这里去"或"导航"按钮
    private static final int STEP_CONFIRM_NAVI        = 6;   // 确认开始导航

    private final Handler handler = new Handler(Looper.getMainLooper());
    private int step = STEP_IDLE;
    private String targetDestination = "";
    private long lastHandledRequestId = -1L;
    private long stepStartTime = 0L;

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        AccessibilityServiceInfo info = new AccessibilityServiceInfo();
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                | AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
                | AccessibilityEvent.TYPE_VIEW_CLICKED; // 补充点击事件，提升响应
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

                String windowClass = event.getClassName() != null ? event.getClassName().toString() : "";
                // 若已出现搜索页 EditText（顶部输入框），跳过首页点击搜索条
                AccessibilityNodeInfo rootProbe = getRootInActiveWindow();
                try {
                    if (rootProbe != null && findSearchPageEditText(rootProbe) != null) {
                        step = STEP_INPUT_DESTINATION;
                        Log.d(TAG, "✅ 已检测到搜索页输入框，跳过首页点击搜索条");
                    } else if (isSearchPage(windowClass) || isSearchResultPage(windowClass)) {
                        step = STEP_INPUT_DESTINATION;
                        Log.d(TAG, "✅ 根据 Activity 判断已在搜索流程，跳过首页点击搜索条");
                    } else {
                        step = STEP_CLICK_SEARCH_BOX;
                        Log.d(TAG, "✅ 进入首页点击搜索框步骤");
                    }
                } finally {
                    if (rootProbe != null) {
                        rootProbe.recycle();
                    }
                }
            } else {
                Log.w(TAG, "⚠️ 任务ID有效，但目的地为空，不启动流程");
            }
        }

        if (step == STEP_IDLE) return;

        // 超时重置（20秒）
        if (System.currentTimeMillis() - stepStartTime > 20000) {
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
                || windowClass.contains("InputSearchActivity"); // 补充搜索页Activity
    }

    private boolean isSearchResultPage(String windowClass) {
        if (windowClass.isEmpty()) return false;
        return windowClass.contains("ResultActivity")
                || windowClass.contains("PoiResultActivity")
                || windowClass.contains("SearchResultActivity")
                || windowClass.contains("PoiListActivity"); // 补充结果页Activity
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
                        handler.postDelayed(this, 800); // 给页面跳转留足时间
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
                        handler.postDelayed(this, 500);
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
                    } else if (clickResultRowByDestination(root, targetDestination)) {
                        // 部分版本输入后列表已出现，无需再点「搜索」
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
        }
    };

    @Override
    public void onInterrupt() {
        Log.w(TAG, "AmapAutoService 被中断");
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
     * 步骤1：点击首页搜索条（截图：maphome_searchbar_bg / txt_hotword / 搜索框 content-desc）
     */
    private boolean clickSearchBox(AccessibilityNodeInfo root) {
        if (clickByViewId(root, ID_HOME_SEARCHBAR_BG)) return true;
        if (clickByViewId(root, ID_HOME_SEARCHBAR_CONTAINER)) return true;
        if (clickByViewId(root, ID_HOME_TXT_HOTWORD)) return true;
        if (clickByAnyDesc(root, "搜索框", "查找地点", "公交", "地铁")) return true;
        if (clickByAnyText(root, SEARCH_PLACEHOLDER)) return true;
        return false;
    }

    /**
     * 步骤2：在搜索页顶部 EditText 输入目的地（截图：EditText 文案为「查找地点、公交、地铁」）
     */
    private boolean inputDestination(AccessibilityNodeInfo root, String destination) {
        AccessibilityNodeInfo input = findSearchPageEditText(root);
        if (input == null) {
            Log.w(TAG, "⚠️ 未找到带占位符的输入框，尝试找第一个EditText兜底");
            input = findFirstNodeByClass(root, "android.widget.EditText");
        }
        if (input == null) {
            Log.e(TAG, "❌ 完全找不到输入框，输入失败");
            return false;
        }

        // 先聚焦，再清空原有内容，再输入
        input.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
        input.performAction(AccessibilityNodeInfo.ACTION_SELECT, null); // 全选
        input.performAction(AccessibilityNodeInfo.ACTION_CUT, null); // 清空
        Bundle args = new Bundle();
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, destination);
        boolean ok = input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
        if (ok) {
            Log.d(TAG, "✅ 已成功填入目的地: " + destination);
        }
        return ok;
    }

    /**
     * 步骤3：点击搜索页右上角「搜索」按钮（截图）
     */
    private boolean clickSearchButton(AccessibilityNodeInfo root) {
        if (clickByViewId(root, ID_SEARCH_BTN_LEGACY)) return true;
        if (clickByAnyText(root, "搜索")) return true;
        if (clickByAnyDesc(root, "搜索")) return true;
        return false;
    }

    /**
     * 步骤4：点击列表里对应地址（截图：结果行 ViewGroup content-desc 为 POI 名称，如「君汇上城」）
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
     * 步骤5：POI 详情底栏点击「导航」（截图：android.view.View text="导航"）
     */
    private boolean clickGoHereButton(AccessibilityNodeInfo root) {
        if (clickNavigateTextButton(root)) return true;
        if (clickByAnyText(root, "开始导航", "到这里去")) return true;
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
        if (clickByAnyText(root, "开始导航", "确定", "确认")) return true;
        if (clickByAnyDesc(root, "开始导航")) return true;
        return false;
    }

    /** 搜索页：优先找顶部带占位文案的 EditText */
    private AccessibilityNodeInfo findSearchPageEditText(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> all = flatten(root);
        for (AccessibilityNodeInfo node : all) {
            if (node == null) continue;
            CharSequence cls = node.getClassName();
            if (cls == null || !"android.widget.EditText".contentEquals(cls)) continue;
            CharSequence tx = node.getText();
            if (tx != null && tx.toString().contains(SEARCH_PLACEHOLDER)) {
                Log.d(TAG, "✅ 找到带占位符的搜索输入框");
                return node;
            }
        }
        AccessibilityNodeInfo first = findFirstNodeByClass(root, "android.widget.EditText");
        if (first != null) {
            Log.w(TAG, "⚠️ 未找到带占位符的输入框，使用第一个EditText兜底");
            return first;
        }
        Log.e(TAG, "❌ 完全找不到EditText节点");
        return null;
    }

    /** 按 content-desc 匹配 POI 名称点击整行（与 Inspector 截图一致） */
    private boolean clickResultRowByDestination(AccessibilityNodeInfo root, String destination) {
        if (destination == null || destination.trim().isEmpty()) return false;
        String key = destination.trim();
        List<AccessibilityNodeInfo> all = flatten(root);
        for (AccessibilityNodeInfo node : all) {
            if (node == null) continue;
            CharSequence cd = node.getContentDescription();
            if (cd == null) continue;
            String d = cd.toString().trim();
            if (d.isEmpty()) continue;
            if (d.equals(key) || d.contains(key) || key.contains(d)) {
                if (performClick(node)) {
                    Log.d(TAG, "✅ 通过 content-desc 点击结果行: " + d);
                    return true;
                }
                AccessibilityNodeInfo parent = findClickableParent(node);
                if (parent != null && performClick(parent)) {
                    Log.d(TAG, "✅ 通过 content-desc 父节点点击结果行: " + d);
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * 详情页底部「导航」：优先从树末尾向前找 text 精确为「导航」的节点（避免点到其它区域的「导航」文案）
     */
    private boolean clickNavigateTextButton(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> all = flatten(root);
        for (int i = all.size() - 1; i >= 0; i--) {
            AccessibilityNodeInfo node = all.get(i);
            if (node == null) continue;
            CharSequence t = node.getText();
            if (t == null) continue;
            if ("导航".contentEquals(normalizeUiText(t.toString()))) {
                if (performClick(node)) {
                    Log.d(TAG, "✅ 已点击底栏「导航」");
                    return true;
                }
            }
        }
        for (AccessibilityNodeInfo node : all) {
            if (node == null) continue;
            CharSequence t = node.getText();
            if (t == null) continue;
            if ("导航".contentEquals(normalizeUiText(t.toString())) && performClick(node)) {
                Log.d(TAG, "✅ 已点击「导航」（正序兜底）");
                return true;
            }
        }
        return false;
    }

    private static String normalizeUiText(String raw) {
        if (raw == null) return "";
        String s = raw.trim();
        if (s.contains("<") && s.contains(">")) {
            s = s.replaceAll("<[^>]+>", "");
        }
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
                if (tx != null && tx.toString().contains(SEARCH_PLACEHOLDER)) return true;
            }
            cur = cur.getParent();
        }
        return false;
    }

    private boolean isInNavigationMode(AccessibilityNodeInfo root) {
        // 检测导航模式特征：显示路线、方向指南、距离信息等
        if (nodeExistsByText(root, "剩余")) return true;
        if (nodeExistsByText(root, "公里")) return true;
        if (nodeExistsByText(root, "米")) return true;
        if (nodeExistsByDesc(root, "导航")) return true;
        if (nodeExistsByText(root, "路线")) return true;
        if (nodeExistsByText(root, "前方")) return true; // 补充导航语音特征
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
        int skipCount = 0;
        for (AccessibilityNodeInfo node : all) {
            CharSequence text = node.getText();
            if (text != null) {
                String t = text.toString();
                // 跳过广告标识
                if (t.contains("广告") || t.contains("推广")) {
                    skipCount++;
                    continue;
                }
                // 跳过过短的无意义文字
                if (t.trim().length() < 2) continue;
                // 点击有文字且有可点击父节点的节点
                AccessibilityNodeInfo clickable = findClickableParent(node);
                if (clickable != null && performClick(clickable)) {
                    Log.d(TAG, "✅ 点击了第一个结果项: " + t);
                    return true;
                }
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
            if (destination != null && !destination.isEmpty() && clickResultRowByDestination(windowRoot, destination)) {
                return true;
            }
            if (clickFirstResultItem(windowRoot)) return true;
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

    /**
     * 将目的地字符串拆分为关键词列表
     * 例如：「北京市朝阳区三里屯」 → ["北京市朝阳区三里屯", "北京市朝阳区", "三里屯", "三里", "屯"]
     */
    private String[] splitKeywords(String destination) {
        List<String> parts = new ArrayList<>();
        parts.add(destination);
        // 按空格/逗号/号分割
        String[] splits = destination.split("[\\s,，。#]");
        for (String s : splits) {
            s = s.trim();
            if (s.length() >= 2) parts.add(s);
        }
        // 从长到短排序
        parts.sort((a, b) -> b.length() - a.length());
        return parts.toArray(new String[0]);
    }
}