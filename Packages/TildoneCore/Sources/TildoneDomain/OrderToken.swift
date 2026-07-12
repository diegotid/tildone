//
//  OrderToken.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
import Foundation

public enum OrderTokenError: Error, Equatable, Sendable {
    case empty
    case invalidCharacter(Character)
    case nonCanonicalEnding
    case invalidBounds
}

/// A variable-length fractional position whose raw value sorts lexicographically.
///
/// Tokens use a restricted ASCII alphabet and never end in its minimum digit.
/// That canonical form leaves room between any two valid tokens without
/// rewriting neighboring tasks.
public struct OrderToken: Codable, Hashable, Comparable, Sendable {
    public static let recommendedMaximumLength = 32

    private static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
    private static let values = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })

    public let rawValue: String

    public init(rawValue: String) throws {
        guard !rawValue.isEmpty else { throw OrderTokenError.empty }
        for character in rawValue where Self.values[character] == nil {
            throw OrderTokenError.invalidCharacter(character)
        }
        guard rawValue.last != Self.alphabet[0] else {
            throw OrderTokenError.nonCanonicalEnding
        }
        self.rawValue = rawValue
    }

    public var exceedsRecommendedMaximumLength: Bool {
        rawValue.utf8.count > Self.recommendedMaximumLength
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.utf8.lexicographicallyPrecedes(rhs.rawValue.utf8)
    }

    public static func before(_ upperBound: Self) -> Self {
        betweenValidBounds(nil, upperBound)
    }

    public static func after(_ lowerBound: Self) -> Self {
        betweenValidBounds(lowerBound, nil)
    }

    public static func between(_ lowerBound: Self?, _ upperBound: Self?) throws -> Self {
        if let lowerBound, let upperBound, lowerBound >= upperBound {
            throw OrderTokenError.invalidBounds
        }

        return betweenValidBounds(lowerBound, upperBound)
    }

    private static func betweenValidBounds(_ lowerBound: Self?, _ upperBound: Self?) -> Self {
        let lower = lowerBound?.rawValue.compactMap { Self.values[$0] } ?? []
        let upper = upperBound?.rawValue.compactMap { Self.values[$0] } ?? []
        let maximumDigit = Self.alphabet.count - 1
        var result: [Int] = []
        var index = 0

        while true {
            let lowerDigit = index < lower.count ? lower[index] : 0
            let upperDigit = index < upper.count ? upper[index] : maximumDigit

            if lowerDigit == upperDigit {
                result.append(lowerDigit)
                index += 1
                continue
            }

            if upperDigit - lowerDigit > 1 {
                result.append(lowerDigit + (upperDigit - lowerDigit) / 2)
                break
            }

            result.append(lowerDigit)
            index += 1
        }

        return Self(validatedRawValue: String(result.map { Self.alphabet[$0] }))
    }

    private init(validatedRawValue: String) {
        rawValue = validatedRawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        do {
            try self.init(rawValue: rawValue)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid order token: \(error)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
