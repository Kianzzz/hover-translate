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
        expect(!TextLogic.isForeign("你好，世界。", native: "zh-Hans"), "母语为中文时悬停跳过中文")
        expect(!TextLogic.isForeign("   ", native: "zh-Hans"), "悬停时跳过空白")
        expect(TextLogic.isForeign("Changes take effect after restart.", native: "zh-Hans"), "识别英文为外语")
        expect(TextLogic.isForeign("Keep in Dock", native: "zh-Hans"), "短英文按钮也识别为外语")
        expect(TextLogic.isForeign("今日はとても良い天気ですね。", native: "zh-Hans"), "识别日文为外语")
        expect(TextLogic.isForeign("Bonjour, comment allez-vous aujourd'hui ?", native: "zh-Hans"), "识别法文为外语")
        expect(!TextLogic.isForeign("Changes take effect after restart.", native: "en"), "母语为英文时悬停跳过英文")
        expect(TextLogic.isForeign("你好，世界。今天天气很好。", native: "en"), "母语为英文时中文是外语")
        expect(TextLogic.language(of: "Good design makes complex things feel simple.") == "en", "英文来源检测")
        for phrase in ["Keep in Dock", "Sign in", "Show all", "Learn more", "Open file", "Do not disturb", "Download complete",
                       "Settings saved", "Hover text here", "Read more", "Get started", "Release notes", "Dark mode", "Open in new tab"] {
            expect(TextLogic.language(of: phrase) == "en", "短英文不误判为其他语言：" + phrase)
        }
        expect(TextLogic.language(of: "今日はとても良い天気ですね。") == "ja", "假名识别为日文")
        expect(TextLogic.language(of: "苹果・华为发布会——最新消息") == "zh-Hans", "中文里的间隔号不当作日文")
        expect(TextLogic.language(of: "使用 iPhone 拍照") == "zh-Hans", "中英混排以中文为主")
        expect(TextLogic.plausibleOCR("Keep in Dock"), "OCR 正常英文保留")
        expect(TextLogic.plausibleOCR("Good design makes complex things feel simple."), "OCR 正常句子保留")
        expect(!TextLogic.plausibleOCR("Tl rn"), "OCR 乱码丢弃")
        expect(!TextLogic.plausibleOCR("Hxq zrwt vlmk"), "OCR 中文误读成的字母串丢弃")
        expect(!TextLogic.plausibleOCR("·"), "OCR 无字母内容丢弃")
        expect(TextLogic.language(of: "東京駅で待っています") == "ja", "汉字夹假名识别为日文")
        expect(TextLogic.language(of: "안녕하세요, 만나서 반갑습니다") == "ko", "识别韩文")
        expect(TextLogic.language(of: "Привет, как дела сегодня?") == "ru", "识别俄文")
        expect(TextLogic.language(of: "Ich habe heute keine Zeit, weil ich arbeiten muss.") == "de", "识别德文")
        expect(TextLogic.language(of: "La conception simple rend les choses complexes plus faciles à comprendre.") == "fr", "法文来源检测")
        expect(TextLogic.target(for: "en", preferred: "zh-Hans", native: "zh-Hans") == "zh-Hans", "默认译成中文")
        expect(TextLogic.target(for: "zh-Hans", preferred: "zh-Hans", native: "zh-Hans") == "en", "中文原文回退译成英文")
        expect(TextLogic.target(for: "ja", preferred: "ja", native: "zh-Hans") == "zh-Hans", "原文已是目标语言时译成母语")
        expect(TextLogic.target(for: "en", preferred: "fr", native: "zh-Hans") == "fr", "可设置其他目标语言")
        expect(TextLogic.target(for: TextLogic.language(of: "你好，世界"), preferred: "zh-Hans", native: "zh-Hans") == "en", "短中文不被当作繁简互译")
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
        expect(longHeight == CardLayout.maximumBodyHeight, "长译文到 260 点上限后滚动阅读")
        let mediumHeight = CardLayout.bodyHeight(result: String(repeating: "一段更完整的中文翻译，保留上下文。", count: 8), width: 360, loading: false, choosing: false, failure: false)
        expect(mediumHeight > 60 && mediumHeight < CardLayout.maximumBodyHeight, "中等译文高度自适应增长")
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
        let twoLineBlock = CGRect(x: 100, y: 300, width: 400, height: 56)
        let blockPointer = CGPoint(x: 260, y: 328)
        let blockBadge = TextLogic.badgeFrame(pointer: blockPointer, visible: CGRect(x: 0, y: 0, width: 1000, height: 800), source: twoLineBlock)
        expect(TextLogic.distance(blockPointer, to: blockBadge) <= 12, "两行文字块中间悬停时图标贴近鼠标")
        let paddedLine = CGRect(x: 100, y: 300, width: 400, height: 36)
        let paddedBadge = TextLogic.badgeFrame(pointer: CGPoint(x: 260, y: 318), visible: CGRect(x: 0, y: 0, width: 1000, height: 800), source: paddedLine)
        expect(TextLogic.distance(CGPoint(x: 260, y: 318), to: paddedBadge) <= 24, "带留白的控件边缘较远时不贴边")
        let huge = TextLogic.badgeFrame(pointer: origin, visible: CGRect(x: 0, y: 0, width: 1000, height: 800), source: CGRect(x: 0, y: 0, width: 1000, height: 800))
        expect(TextLogic.distance(origin, to: huge) < 10, "容器级边界不能把图标推远")
        let wrapped = "Previous sentence. This sentence continues across\na visual line break and ends here. Next sentence."
        let wrappedOffset = (wrapped as NSString).range(of: "visual").location
        expect(TextLogic.segment(wrapped, utf16Offset: wrappedOffset, word: false) == "This sentence continues across a visual line break and ends here.", "系统取词跨软换行提取完整句子")
        let paragraphs = "First paragraph without punctuation\n\nSecond paragraph without punctuation"
        expect(TextLogic.segment(paragraphs, utf16Offset: 8, word: false) == "First paragraph without punctuation", "空行隔开的段落不能混在一起")
        let crlf = "A sentence continues\r\non the next line."
        expect(TextLogic.segment(crlf, utf16Offset: 24, word: false) == "A sentence continues  on the next line.", "CRLF 换行不误判为段落分隔")
        let split = "你好 🌿。A long sentence wraps\nacross this line."
        expect(TextLogic.segment(split, utf16Offset: (split as NSString).range(of: "across").location, word: false) == "A long sentence wraps across this line.", "跨行与 emoji UTF16 偏移保持准确")
        func ocrLine(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat = 420) -> TextLogic.OCRLine {
            TextLogic.OCRLine(text: text, bounds: CGRect(x: x, y: y, width: width, height: 20))
        }
        let context = [ocrLine("Earlier sentence. This is a long sentence that", 100, 100),
                       ocrLine("continues on the next line and needs context", 100, 128),
                       ocrLine("to translate correctly. Another sentence.", 100, 156),
                       ocrLine("A separate paragraph should stay separate.", 100, 210),
                       ocrLine("An unrelated sidebar should never be included.", 620, 128)]
        expect(TextLogic.ocrSentence(lines: context, hit: 1, offset: 5) == "This is a long sentence that continues on the next line and needs context to translate correctly.", "OCR 合并跨三行句子并隔离相邻栏目")
        expect(TextLogic.ocrSentence(lines: context, hit: 2, offset: 30) == "Another sentence.", "同一行按鼠标位置选中正确句子")
        expect(TextLogic.ocrSentence(lines: context, hit: 3, offset: 10) == context[3].text, "段落间距阻止跨段合并")
        let menu = [ocrLine("Keep in Dock", 100, 100, 110), ocrLine("Open at Login", 100, 128, 110)]
        expect(TextLogic.ocrSentence(lines: menu, hit: 0, offset: 3) == "Keep in Dock", "短菜单项不能拼成段落")
        let missing = [ocrLine("Text on the first line of a longer paragraph", 100, 100), ocrLine("Text in a distant paragraph should not join.", 100, 260)]
        expect(TextLogic.ocrSentence(lines: missing, hit: 0, offset: 10) == missing[0].text, "较大空隙不能跨越")
        print("84 core checks passed.")
    }
    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        DiagnosticCheck.require(condition(), name)
        print("PASS: \(name)")
    }
}
