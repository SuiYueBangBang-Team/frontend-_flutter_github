# -*- coding: utf-8 -*-
from pathlib import Path

p = Path(__file__).resolve().parent / "android/app/src/main/java/com/example/phone_java/WeChatAutoService.java"
t = p.read_text(encoding="utf-8")

insert_method = """
    private AccessibilityNodeInfo findPlusMenuRowLayout(AccessibilityNodeInfo node) {
        AccessibilityNodeInfo cur = node;
        while (cur != null) {
            String resId = cur.getViewIdResourceName();
            if (resId != null
                    && (ID_SCAN_MENU_ROW_M7G.equals(resId) || ID_SCAN_MENU_ROW_N7G.equals(resId))) {
                return cur;
            }
            cur = cur.getParent();
        }
        return null;
    }

"""

old1 = """                    Log.d(TAG, "【扫一扫-2】精确匹配文案节点");
                    AccessibilityNodeInfo clickableParent = findClickableParent(textNode);
                    if (clickableParent != null
                            && (performClick(clickableParent) || forceBubbleClick(clickableParent))) {
                        Log.d(TAG, "【扫一扫-2】点击可点击父行成功");
                        return true;
                    }
                    if (performClick(textNode) || forceBubbleClick(textNode)) {
                        Log.d(TAG, "【扫一扫-2】点击文案节点成功");
                        return true;
                    }"""

new1 = """                    Log.d(TAG, "【扫一扫-2】精确匹配文案节点");
                    AccessibilityNodeInfo menuRow = findPlusMenuRowLayout(textNode);
                    if (menuRow != null
                            && (performClick(menuRow) || forceBubbleClick(menuRow))) {
                        Log.d(TAG, "【扫一扫-2】点击 m7g/n7g 菜单行成功");
                        return true;
                    }
                    AccessibilityNodeInfo clickableParent = findClickableParent(textNode);
                    if (clickableParent != null
                            && (performClick(clickableParent) || forceBubbleClick(clickableParent))) {
                        Log.d(TAG, "【扫一扫-2】点击可点击父节点成功");
                        return true;
                    }
                    if (performClick(textNode) || forceBubbleClick(textNode)) {
                        Log.d(TAG, "【扫一扫-2】点击文案节点成功");
                        return true;
                    }"""

old2 = """                    Log.d(TAG, "【扫一扫-2】obc + 文案双重匹配");
                    if (performClick(node) || forceBubbleClick(node)) return true;
                    AccessibilityNodeInfo clickableParent = findClickableParent(node);
                    if (clickableParent != null
                            && (performClick(clickableParent) || forceBubbleClick(clickableParent))) return true;"""

new2 = """                    Log.d(TAG, "【扫一扫-2】obc + 文案双重匹配");
                    if (performClick(node) || forceBubbleClick(node)) return true;
                    AccessibilityNodeInfo menuRow = findPlusMenuRowLayout(node);
                    if (menuRow != null && (performClick(menuRow) || forceBubbleClick(menuRow))) return true;
                    AccessibilityNodeInfo clickableParent = findClickableParent(node);
                    if (clickableParent != null
                            && (performClick(clickableParent) || forceBubbleClick(clickableParent))) return true;"""

anchor = "    private static boolean nodeTextEquals(AccessibilityNodeInfo node, String expected) {"

if "findPlusMenuRowLayout" in t:
    print("already patched")
    raise SystemExit(0)
assert old1 in t, "old1 missing"
assert old2 in t, "old2 missing"
assert anchor in t, "anchor missing"

t = t.replace(old1, new1).replace(old2, new2).replace(anchor, insert_method + anchor)
p.write_text(t, encoding="utf-8", newline="\n")
print("patched ok")
