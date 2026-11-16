// InputSettings.swift: per-input user settings (rename, enable/disable, playback target) and the merged catalog.
//
// Purpose: the amp knows inputs only as numbers; the model table gives default names; the user renames, hides
//   and maps each to a playback target. `InputCatalog` merges the three into what views and intents show.
// Context: pure functions over value types so they are trivially testable. An input with no stored setting is
//   enabled, carries its default name and has no playback target.
// Dependencies: HegelProtocol (AmpModel), PlaybackTarget.
import Foundation
import HegelProtocol

/// What the user changed about one input. Stored as a list in SettingsStore.
public struct InputSetting: Hashable, Sendable, Codable, Identifiable {
    public var number: Int
    /// User name; nil or empty keeps the model's default.
    public var name: String?
    public var isEnabled: Bool
    public var playbackTarget: PlaybackTarget?

    public var id: Int { number }

    public init(number: Int, name: String? = nil, isEnabled: Bool = true, playbackTarget: PlaybackTarget? = nil) {
        self.number = number
        self.name = name
        self.isEnabled = isEnabled
        self.playbackTarget = playbackTarget
    }
}

/// One input as the UI sees it: resolved name, enabled flag and playback target.
public struct InputItem: Hashable, Sendable, Identifiable {
    public var number: Int
    public var name: String
    public var defaultName: String
    public var isEnabled: Bool
    public var playbackTarget: PlaybackTarget?

    public var id: Int { number }
    public var isRenamed: Bool { name != defaultName }
}

public enum InputCatalog {
    /// Every input of the model, in number order, with user settings applied. Inputs the model table does not
    /// list (e.g. Röst) fall back to "Input n" so a settings entry can still address them.
    public static func items(model: AmpModel, settings: [InputSetting]) -> [InputItem] {
        let byNumber = Dictionary(settings.map { ($0.number, $0) }, uniquingKeysWith: { _, last in last })
        let numbers = model.inputs.isEmpty ? Array(1...12) : model.inputs.map(\.number)
        return numbers.map { n in
            let defaultName = model.inputName(n) ?? "Input \(n)"
            let s = byNumber[n]
            let custom = s?.name?.trimmingCharacters(in: .whitespaces)
            return InputItem(
                number: n,
                name: (custom?.isEmpty == false) ? custom! : defaultName,
                defaultName: defaultName,
                isEnabled: s?.isEnabled ?? true,
                playbackTarget: s?.playbackTarget)
        }
    }

    public static func enabledItems(model: AmpModel, settings: [InputSetting]) -> [InputItem] {
        items(model: model, settings: settings).filter(\.isEnabled)
    }

    public static func item(number: Int, model: AmpModel, settings: [InputSetting]) -> InputItem? {
        items(model: model, settings: settings).first { $0.number == number }
    }

    /// Finds an input by what the user calls it (case- and whitespace-insensitive), then by its default name,
    /// then by "input N" / a bare number. Used by Siri ("switch to Pontus").
    public static func match(name query: String, model: AmpModel, settings: [InputSetting]) -> InputItem? {
        let q = normalize(query)
        guard !q.isEmpty else { return nil }
        let all = items(model: model, settings: settings)
        if let hit = all.first(where: { normalize($0.name) == q }) { return hit }
        if let hit = all.first(where: { normalize($0.defaultName) == q }) { return hit }
        let digits = q.replacingOccurrences(of: "input", with: "").trimmingCharacters(in: .whitespaces)
        if let n = Int(digits) { return all.first { $0.number == n } }
        // Last resort: a unique prefix match on the user name ("pont" -> "Pontus").
        let prefixed = all.filter { normalize($0.name).hasPrefix(q) }
        return prefixed.count == 1 ? prefixed[0] : nil
    }

    public static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Returns `settings` with `change` applied to one input (replacing any earlier entry for that number).
    public static func updating(_ settings: [InputSetting], with change: InputSetting) -> [InputSetting] {
        var out = settings.filter { $0.number != change.number }
        out.append(change)
        return out.sorted { $0.number < $1.number }
    }

    /// The next enabled input after `current`, wrapping around; nil when none is enabled.
    public static func next(after current: Int?, model: AmpModel, settings: [InputSetting]) -> InputItem? {
        let enabled = enabledItems(model: model, settings: settings)
        guard !enabled.isEmpty else { return nil }
        guard let current, let i = enabled.firstIndex(where: { $0.number == current }) else { return enabled[0] }
        return enabled[(i + 1) % enabled.count]
    }
}
