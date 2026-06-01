//
//  RecruitmentDatabase.swift
//  AKHelper
//
//  Created on 2026/6/1.
//

import Foundation

struct RecruitmentDatabase: Decodable {
    let server: String
    let updatedAt: String
    let operators: [RecruitmentOperator]
}

struct RecruitmentOperator: Decodable {
    let id: String
    let name: String
    let rarity: Int
    let tags: [String]
}

struct RecruitmentTagMatcher {
    let canonicalTags: [String]
    private let normalizedAliases: [String: String]

    init(operators: [RecruitmentOperator]) {
        var orderedTags: [String] = []
        var seenTags = Set<String>()

        for operatorInfo in operators {
            for tag in operatorInfo.tags where seenTags.insert(tag).inserted {
                orderedTags.append(tag)
            }
        }

        canonicalTags = orderedTags

        var aliases: [String: String] = [:]
        for tag in orderedTags {
            aliases[Self.normalizedText(tag)] = tag

            if tag.hasSuffix("干员"), tag != "资深干员", tag != "高级资深干员" {
                let shortTag = String(tag.dropLast(2))
                aliases[Self.normalizedText(shortTag)] = tag
            }
        }

        normalizedAliases = aliases
    }

    func matchedTags(in recognizedText: [String]) -> [String] {
        let normalizedObservations = recognizedText.map(Self.normalizedText)
        let mergedText = normalizedObservations.joined(separator: " ")

        let matchedTags = canonicalTags.filter { tag in
            let canonicalTag = Self.normalizedText(tag)
            if mergedText.contains(canonicalTag) {
                return true
            }

            if tag.hasSuffix("干员"), tag != "资深干员", tag != "高级资深干员" {
                let shortTag = Self.normalizedText(String(tag.dropLast(2)))
                return mergedText.contains(shortTag)
            }

            return false
        }

        return removeContainedTagFalsePositives(
            from: matchedTags,
            normalizedObservations: normalizedObservations
        )
    }

    func canonicalTag(for tag: String) -> String? {
        normalizedAliases[Self.normalizedText(tag)]
    }

    private func removeContainedTagFalsePositives(
        from matchedTags: [String],
        normalizedObservations: [String]
    ) -> [String] {
        var filteredTags = Set(matchedTags)
        let containedTagRules = [
            (longTag: "高级资深干员", shortTag: "资深干员"),
            (longTag: "支援机械", shortTag: "支援")
        ]

        for rule in containedTagRules {
            guard filteredTags.contains(rule.longTag), filteredTags.contains(rule.shortTag) else {
                continue
            }

            if !hasIndependentEvidence(
                for: rule.shortTag,
                excluding: rule.longTag,
                in: normalizedObservations
            ) {
                filteredTags.remove(rule.shortTag)
            }
        }

        return canonicalTags.filter { filteredTags.contains($0) }
    }

    private func hasIndependentEvidence(
        for shortTag: String,
        excluding longTag: String,
        in normalizedObservations: [String]
    ) -> Bool {
        let normalizedShortTag = Self.normalizedText(shortTag)
        let normalizedLongTag = Self.normalizedText(longTag)

        return normalizedObservations.contains { observation in
            observation.contains(normalizedShortTag) && !observation.contains(normalizedLongTag)
        }
    }

    nonisolated private static func normalizedText(_ text: String) -> String {
        text.filter { character in
            character.isLetter || character.isNumber
        }
    }
}

enum RecruitmentDatabaseLoader {
    static func load() throws -> RecruitmentDatabase {
        guard let url = Bundle.main.url(forResource: "recruitment", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RecruitmentDatabase.self, from: data)
    }
}
