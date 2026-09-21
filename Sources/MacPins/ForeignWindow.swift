import AppKit

struct ForeignWindow: Hashable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect

    var displayName: String {
        guard !title.isEmpty else { return ownerName }
        let shortened = title.count > 42 ? String(title.prefix(42)) + "…" : title
        return "\(ownerName) — \(shortened)"
    }

    static func == (lhs: ForeignWindow, rhs: ForeignWindow) -> Bool {
        lhs.windowID == rhs.windowID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
    }
}
