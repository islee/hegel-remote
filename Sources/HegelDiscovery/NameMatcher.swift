// NameMatcher.swift: pure matcher from a Bonjour service name to an AmpModel.
//
// Purpose: decide whether an advertised `_raop` / `_airplay` service might be a Hegel amp.
// Context: the H590 advertises `_raop` as `D8F710D3E204@H590` and `_airplay` as `H590`. A match only makes
//   a candidate; discovery still confirms by talking to port 50001.
// Dependencies: HegelProtocol (the model table), Foundation (diacritic folding).
import Foundation
import HegelProtocol

public enum HegelNameMatcher {
    /// The model whose alias appears in `serviceName`, or nil.
    /// An alias must start at a boundary (not preceded by a letter or digit) and not be followed by a
    /// digit, so `H190V` matches H190, `XH590` and `H5900` match nothing, and `Frost` is not Röst.
    public static func model(forServiceName serviceName: String) -> AmpModel? {
        let folded = serviceName.folding(options: .diacriticInsensitive, locale: nil).uppercased()
        let chars = Array(folded)
        for model in AmpModel.all {
            for alias in model.aliases {
                let a = Array(alias)
                guard !a.isEmpty, chars.count >= a.count else { continue }
                for start in 0...(chars.count - a.count) where Array(chars[start..<start + a.count]) == a {
                    let before = start > 0 ? chars[start - 1] : nil
                    let after = start + a.count < chars.count ? chars[start + a.count] : nil
                    let boundaryBefore = before.map { !$0.isLetter && !$0.isNumber } ?? true
                    let digitAfter = after.map { $0.isNumber } ?? false
                    if boundaryBefore && !digitAfter { return model }
                }
            }
        }
        return nil
    }

    public static func isCandidate(_ serviceName: String) -> Bool {
        model(forServiceName: serviceName) != nil
    }
}
