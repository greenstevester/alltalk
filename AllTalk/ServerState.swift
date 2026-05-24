import Foundation

/// Lifecycle state of the local llama-server, published by `LlamaServerManager`.
/// Pure value type (no AppKit) so it is unit-testable in isolation.
enum ServerState: Equatable {
    case stopped
    case starting
    case ready
    case error(String)

    /// Label for the disabled status line at the top of the menu.
    var menuLabel: String {
        switch self {
        case .stopped:          return "○ Model: Stopped"
        case .starting:         return "◐ Model: Starting…"
        case .ready:            return "● Model: Ready"
        case .error(let why):   return "⚠ Model: \(why)"
        }
    }

    /// True while a server is up or coming up — drives the menu toggle wording.
    var isActive: Bool {
        switch self {
        case .starting, .ready: return true
        case .stopped, .error:  return false
        }
    }
}
