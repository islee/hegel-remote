// IconChoice.swift: which app icon the user wants, and the data about which model icons exist.
//
// Purpose: pure logic for the "App icon" setting: the choice type, its storage form, the names the platforms
//   need (iOS alternate icon name, Mac Dock image name) and the "icon follows the amp model" rule.
// Context: the artwork comes from scripts/make_icon.py (`MODELS`); `AppIcons.availableModelIcons` must list the
//   same models, plus the alternate name in project.yml. Adding a model icon is data in those three places.
// Dependencies: Foundation.
import Foundation

public enum IconChoice: Hashable, Sendable {
    case `default`
    /// A per-model icon, by upper-case model name ("H590").
    case model(String)

    /// UserDefaults form: "default" or the model name.
    public var storageValue: String {
        switch self {
        case .default: "default"
        case .model(let id): id
        }
    }

    public init(storageValue: String?) {
        guard let v = storageValue?.trimmingCharacters(in: .whitespaces), !v.isEmpty, v.lowercased() != "default" else {
            self = .default
            return
        }
        self = .model(v.uppercased())
    }

    /// `UIApplication.setAlternateIconName` argument: nil selects the primary icon.
    public var alternateIconName: String? {
        switch self {
        case .default: nil
        case .model(let id): "AppIcon-\(id)"
        }
    }

    /// Asset-catalog image set the Mac app shows in the Dock for the given appearance.
    public func dockImageName(dark: Bool) -> String {
        let name: String
        switch self {
        case .default: name = "Default"
        case .model(let id): name = id
        }
        return "DockIcon-\(name)-\(dark ? "Dark" : "Light")"
    }

    public var label: String {
        switch self {
        case .default: "Default"
        case .model(let id): id
        }
    }
}

public enum AppIcons {
    /// Models that have an icon in the asset catalog. Add the model here when its artwork ships.
    public static let availableModelIcons = ["H590"]

    /// The choices the picker offers: the default, then one per available model.
    public static var choices: [IconChoice] { [.default] + availableModelIcons.map { IconChoice.model($0) } }

    public static func isAvailable(_ choice: IconChoice) -> Bool {
        switch choice {
        case .default: true
        case .model(let id): availableModelIcons.contains(id.uppercased())
        }
    }

    /// What to actually apply: a stored choice whose artwork does not exist (a removed model) means the default.
    public static func effective(_ choice: IconChoice) -> IconChoice {
        isAvailable(choice) ? choice : .default
    }

    /// The icon for an amp model: its own artwork when it has some, else the default icon.
    public static func icon(forModelID id: String) -> IconChoice {
        effective(.model(id.uppercased()))
    }
}
