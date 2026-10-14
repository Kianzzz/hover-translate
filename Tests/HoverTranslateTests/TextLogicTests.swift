import Foundation

@main
struct CoreChecks {
    static func main() {
        let text = "First sentence. Second sentence. Third sentence."
        expect(TextLogic.segment(text, utf16Offset: 20, word: false) == "Second sentence.", "只提取鼠标所在句子")
        expect(TextLogic.segment(text, utf16Offset: 20, word: true) == "Second", "精确提取所在单词")
        expect(TextLogic.segment(text, utf16Offset: 200, word: false) == nil, "拒绝越界位置")
        let unicode = "你好 🌿。Good design matters."
        let offset = (unicode as NSString).range(of: "design").location
        expect(TextLogic.segment(unicode, utf16Offset: offset, word: true) == "design", "中文与 emoji 不影响 UTF16 定位")
        expect(!TextLogic.hasEnglish("你好，世界。"), "悬停时跳过纯中文")
        expect(!TextLogic.hasEnglish("   "), "悬停时跳过空白")
        expect(TextLogic.hasEnglish("Changes take effect after restart."), "识别英文")
        let quartz = TextLogic.quartzPoint(CGPoint(x: -400, y: 1000), desktopTop: 900)
        expect(quartz == CGPoint(x: -400, y: -100), "副屏负坐标转换")
        let cocoa = TextLogic.cocoaRect(CGRect(x: -400, y: -100, width: 100, height: 20), desktopTop: 900)
        expect(cocoa == CGRect(x: -400, y: 980, width: 100, height: 20), "文字边界坐标转换")
        let visible = CGRect(x: -1200, y: 0, width: 1200, height: 800)
        let frame = TextLogic.panelFrame(anchor: CGRect(x: -20, y: 20, width: 10, height: 20), size: CGSize(width: 420, height: 360), visible: visible)
        expect(visible.contains(frame), "浮窗保持在屏幕内")
        expect(frame.minY > 40, "屏幕底部自动向上显示")
        expect(frame.maxX <= -12, "浮窗不越过屏幕右边缘")
        let badge = TextLogic.badgeFrame(pointer: CGPoint(x: -15, y: 12), visible: visible)
        expect(visible.contains(badge), "角落图标保持在副屏内")
        expect(badge.width == 30 && badge.height == 30, "图标保持小尺寸")
        expect(badge.maxX < -15, "屏幕右边缘时图标放在鼠标左侧")
        expect(badge.minY > 12, "屏幕底部时图标放在鼠标上方")
        let source = CGRect(x: 100, y: 300, width: 300, height: 25)
        let nextBadge = TextLogic.badgeFrame(pointer: CGPoint(x: 150, y: 310), visible: CGRect(x: 0, y: 0, width: 1100, height: 780))
        expect(TextLogic.hoverTransitContains(CGPoint(x: nextBadge.midX, y: 299), from: source, to: nextBadge), "文字到图标之间可以通行")
        expect(!TextLogic.hoverTransitContains(CGPoint(x: 900, y: 700), from: source, to: nextBadge), "无关屏幕区域不保留旧图标")
        let shortWidth = CardLayout.width(source: "Keep in Dock", result: "保留在程序坞")
        let sentenceWidth = CardLayout.width(source: "Good design makes complex things feel simple.", result: "好的设计，让复杂的事情变得简单。")
        let longWidth = CardLayout.width(source: String(repeating: "English text. ", count: 40), result: String(repeating: "较长的译文。", count: 100))
        expect(shortWidth == 240, "短语浮窗收紧至 240 点")
        expect(sentenceWidth > shortWidth && sentenceWidth <= 520, "完整句子向两边展开")
        expect(longWidth == 520, "长段落限制最大宽度")
        let shortHeight = CardLayout.bodyHeight(result: "保留在程序坞", width: shortWidth, loading: false, choosing: false, failure: false)
        let longHeight = CardLayout.bodyHeight(result: String(repeating: "较长的译文。", count: 100), width: longWidth, loading: false, choosing: false, failure: false)
        expect(shortHeight + 64 <= 90, "短语浮窗整体高度不超过 90 点")
        expect(longHeight == 60, "长译文限制在三行附近并滚动阅读")
        let draft = "保留🌿 | 你好，世界！ | 不动"
        let selected = "你好，世界！"
        let range = (draft as NSString).range(of: selected)
        let edit = SelectionEdit(value: draft, selected: selected, range: range)
        let translated = edit.replacing(with: "Hello, world!")
        expect(translated == "保留🌿 | Hello, world! | 不动", "替换仅影响选区并正确处理 emoji UTF16 偏移")
        let restore = SelectionEdit(value: translated!, selected: "Hello, world!", range: NSRange(location: range.location, length: "Hello, world!".utf16.count))
        expect(restore.replacing(with: selected) == draft, "还原使用保存原文并保留未选中的内容")
        expect(SelectionEdit(value: "A A", selected: "A", range: NSRange(location: 2, length: 1)).replacing(with: "B") == "A B", "重复文本按原选区定位")
        expect(SelectionEdit(value: "已改变", selected: selected, range: range).replacing(with: "English") == nil, "内容或选区变化时拒绝替换")
        expect(SelectionEdit(value: draft, selected: "", range: NSRange(location: 0, length: 0)).replacing(with: "English") == nil, "空选区不能插入译文")
        let line = CGRect(x: 100, y: 300, width: 500, height: 22)
        let origin = CGPoint(x: 300, y: 311)
        let nearby = TextLogic.badgeFrame(pointer: origin, visible: CGRect(x: 0, y: 0, width: 1000, height: 800), source: line)
        expect(!nearby.intersects(line), "图标不遮挡已知文字边界")
        expect(TextLogic.distance(origin, to: nearby) <= 18, "长句中间悬停时图标就在附近")
        expect(TextLogic.movingTowardBadge(from: origin, to: CGPoint(x: 303, y: 304), badge: nearby), "斜向接近图标保持可达")
        expect(!TextLogic.movingTowardBadge(from: origin, to: CGPoint(x: 303, y: 322), badge: nearby), "反向离开不保留图标")
        expect(!TextLogic.movingTowardBadge(from: origin, to: origin, badge: nearby), "静止不能无限延续接近状态")
        let huge = TextLogic.badgeFrame(pointer: origin, visible: CGRect(x: 0, y: 0, width: 1000, height: 800), source: CGRect(x: 0, y: 0, width: 1000, height: 800))
        expect(TextLogic.distance(origin, to: huge) < 10, "容器级边界不能把图标推远")
        print("34 core checks passed.")
    }
    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        DiagnosticCheck.require(condition(), name)
        print("PASS: \(name)")
    }
}
