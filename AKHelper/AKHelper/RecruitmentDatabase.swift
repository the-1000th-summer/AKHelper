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
        let mergedText = recognizedText
            .map(Self.normalizedText)
            .joined(separator: " ")

        return canonicalTags.filter { tag in
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
    }

    func canonicalTag(for tag: String) -> String? {
        normalizedAliases[Self.normalizedText(tag)]
    }

    private static func normalizedText(_ text: String) -> String {
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
