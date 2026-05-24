import Foundation

/// Pure, dependency-injected helpers for locating the llama-server binary and the
/// model files. No AppKit and no real filesystem access (the caller injects the
/// checks), which makes these unit-testable.
enum ServerDiscovery {
    /// Filenames expected inside the configured model folder.
    static let modelFileName  = "Voxtral-Mini-3B-2507-Q4_K_M.gguf"
    static let mmprojFileName = "mmproj-Voxtral-Mini-3B-2507-Q8_0.gguf"

    /// Candidate locations for the llama-server binary, in priority order.
    static let binaryCandidates = [
        "/opt/homebrew/bin/llama-server",
        "/usr/local/bin/llama-server",
    ]

    /// Why model resolution failed — carries a human-readable message for the UI.
    struct ModelError: Error, Equatable {
        let message: String
    }

    /// Resolve the llama-server binary path.
    /// `override` (a Settings value) wins when non-empty and executable; otherwise the
    /// first executable candidate is returned, else `nil`.
    static func resolveBinary(override: String,
                              isExecutable: (String) -> Bool) -> String? {
        if !override.isEmpty, isExecutable(override) { return override }
        return binaryCandidates.first(where: isExecutable)
    }

    /// Resolve the model + mmproj file paths inside `folder` (tilde-expanded).
    /// `.success` only when both exist; `.failure` names the missing file(s).
    static func resolveModel(folder: String,
                             fileExists: (String) -> Bool)
        -> Result<(model: String, mmproj: String), ModelError> {
        let expanded = (folder as NSString).expandingTildeInPath
        let model  = (expanded as NSString).appendingPathComponent(modelFileName)
        let mmproj = (expanded as NSString).appendingPathComponent(mmprojFileName)
        var missing: [String] = []
        if !fileExists(model)  { missing.append(modelFileName) }
        if !fileExists(mmproj) { missing.append(mmprojFileName) }
        guard missing.isEmpty else {
            return .failure(ModelError(message: "model not found in \(folder) — missing \(missing.joined(separator: ", "))"))
        }
        return .success((model, mmproj))
    }
}
