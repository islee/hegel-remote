// AmpState.swift: what we currently know about the amp.
//
// Purpose: fold a stream of AmpEvent into one snapshot. A field is nil until the amp reports it.
// Context: the amp broadcasts state to every client, so this is built from a stream, never from replies.
// Dependencies: AmpEvent.

public struct AmpState: Sendable, Equatable, Hashable, Codable {
    public var power: Bool?
    public var input: Int?
    /// Percent 0...100, as last reported (the amp may round a request when a max-volume limit is set).
    public var volume: Int?
    public var mute: Bool?

    public init(power: Bool? = nil, input: Int? = nil, volume: Int? = nil, mute: Bool? = nil) {
        self.power = power
        self.input = input
        self.volume = volume
        self.mute = mute
    }

    /// True once all four fields have been reported.
    public var isComplete: Bool {
        power != nil && input != nil && volume != nil && mute != nil
    }

    /// Folds one event in. Returns true when a field changed value.
    @discardableResult
    public mutating func apply(_ event: AmpEvent) -> Bool {
        let before = self
        switch event {
        case .power(let on): power = on
        case .input(let n): input = n
        case .volume(let v): volume = v
        case .mute(let m): mute = m
        case .resetTimer, .error, .unrecognized, .connection: break
        }
        return self != before
    }
}
