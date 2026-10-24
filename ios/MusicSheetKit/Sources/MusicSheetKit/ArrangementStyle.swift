import Foundation

/// Ready-made rearrangement styles. `prompt` is what the backend sends to the AI.
public struct ArrangementStyle: Hashable, Sendable, Identifiable {
    public var name: String
    public var prompt: String
    public var symbol: String

    public var id: String { name }

    public static let presets: [ArrangementStyle] = [
        .init(name: "民谣", prompt: "木吉他民谣：温暖、简洁，多用加九和挂留和弦，分解或轻扫弦", symbol: "leaf"),
        .init(name: "流行抒情", prompt: "流行抒情：情绪饱满，副歌层层推进，适合边弹边唱", symbol: "heart"),
        .init(name: "R&B", prompt: "R&B / Neo Soul：多用七和弦、九和弦和二五进行，律动慵懒", symbol: "moon.stars"),
        .init(name: "爵士", prompt: "爵士：丰富的七和弦与延伸音，加入二五一和经过和弦，摇摆节奏", symbol: "music.quarternote.3"),
        .init(name: "摇滚", prompt: "摇滚：强力的扫弦和明快的和弦转换，副歌更有冲击力", symbol: "bolt"),
        .init(name: "Bossa Nova", prompt: "Bossa Nova：轻柔的巴萨诺瓦律动，大七和弦和小七和弦为主", symbol: "sun.max"),
        .init(name: "简化版", prompt: "初学者简化版：全曲只用四到五个最常用的和弦，换和弦尽量少", symbol: "hand.thumbsup"),
    ]
}
