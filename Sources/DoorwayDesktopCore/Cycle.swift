/// Moving through a fixed list, wrapping at both ends. Settings uses it for ⌘[ and ⌘] across its tabs.
extension CaseIterable where Self: Equatable, AllCases.Index == Int {
    /// The case `steps` away, e.g. -1 for the previous one. Past the last it starts over at the first, and back.
    public func stepped(by steps: Int) -> Self {
        let all = Self.allCases
        let i = all.firstIndex(of: self) ?? 0
        let count = all.count
        return all[((i + steps) % count + count) % count]
    }
}
