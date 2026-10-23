import Foundation

/// 注音词库（来自小麦注音 McBopomofo，MIT）。
/// 文件每行：读音<TAB>最高分<TAB>词1 词2 …，按 UTF-8 字节序排好。
/// 用内存映射 + 二分查找，键盘扩展内存很紧，不把整个词库读进字典。
final class ZhuyinDictionary {
    static let shared = ZhuyinDictionary()

    struct Entry {
        let score: Double
        let values: [String]
    }

    private let data: Data
    private var lineStarts: [Int32] = []
    private var cache: [String: Entry] = [:]
    private var misses = Set<String>()

    private init() {
        if let url = Bundle.main.url(forResource: "zhuyin", withExtension: "txt", subdirectory: "Zhuyin"),
           let d = try? Data(contentsOf: url, options: .alwaysMapped) {
            data = d
        } else {
            data = Data()
        }
        var starts: [Int32] = []
        starts.reserveCapacity(140_000)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let count = raw.count
            var offset = 0
            while offset < count {
                starts.append(Int32(offset))
                guard let nl = memchr(base + offset, 0x0A, count - offset) else { break }
                offset = base.distance(to: UnsafeRawPointer(nl)) + 1
            }
        }
        lineStarts = starts
    }

    var isLoaded: Bool { !lineStarts.isEmpty }

    func lookup(_ key: String) -> Entry? {
        if let hit = cache[key] { return hit }
        if misses.contains(key) { return nil }
        if cache.count > 3000 { cache.removeAll(keepingCapacity: true) }
        if misses.count > 3000 { misses.removeAll(keepingCapacity: true) }

        let keyBytes = Array(key.utf8)
        var found: Entry?
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let p = raw.bindMemory(to: UInt8.self)
            var lo = 0
            var hi = lineStarts.count - 1
            while lo <= hi {
                let mid = (lo + hi) / 2
                let start = Int(lineStarts[mid])
                var tab = start
                while tab < p.count && p[tab] != 0x09 && p[tab] != 0x0A { tab += 1 }
                let c = Self.compare(keyBytes, p, start, tab)
                if c == 0 {
                    found = Self.parse(p, tab: tab)
                    break
                } else if c < 0 {
                    hi = mid - 1
                } else {
                    lo = mid + 1
                }
            }
        }
        if let found { cache[key] = found } else { misses.insert(key) }
        return found
    }

    private static func compare(_ key: [UInt8], _ p: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> Int {
        let len = end - start
        let n = min(key.count, len)
        for i in 0..<n {
            let a = key[i], b = p[start + i]
            if a != b { return a < b ? -1 : 1 }
        }
        return key.count == len ? 0 : (key.count < len ? -1 : 1)
    }

    private static func parse(_ p: UnsafeBufferPointer<UInt8>, tab: Int) -> Entry? {
        var i = tab + 1
        var scoreEnd = i
        while scoreEnd < p.count && p[scoreEnd] != 0x09 && p[scoreEnd] != 0x0A { scoreEnd += 1 }
        let score = Double(String(decoding: UnsafeBufferPointer(rebasing: p[i..<scoreEnd]), as: UTF8.self)) ?? -20
        i = scoreEnd + 1
        var lineEnd = i
        while lineEnd < p.count && p[lineEnd] != 0x0A { lineEnd += 1 }
        guard i < lineEnd else { return nil }
        let text = String(decoding: UnsafeBufferPointer(rebasing: p[i..<lineEnd]), as: UTF8.self)
        let values = text.split(separator: " ").map(String.init)
        return values.isEmpty ? nil : Entry(score: score, values: values)
    }
}
