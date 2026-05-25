import Foundation

/// Pure helpers for turning a streaming transcript into pasteable pieces. No AppKit, so
/// it is unit-testable in isolation.
enum TranscriptStreaming {
    /// Removes and returns every whitespace-terminated word from `buffer`, leaving any
    /// trailing partial (not-yet-terminated) word in place. Used to paste dictation
    /// word-by-word as tokens stream in, without ever splitting a half-finished word.
    static func drainCompleteWords(from buffer: inout String) -> [String] {
        var words: [String] = []
        while let idx = buffer.firstIndex(where: { $0.isWhitespace }) {
            let end = buffer.index(after: idx)
            words.append(String(buffer[..<end]))
            buffer.removeSubrange(..<end)
        }
        return words
    }
}
