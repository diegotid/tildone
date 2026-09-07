//
//  RichTextTests.swift
//  Tildone
//
import XCTest
@testable import TildoneDomain

final class RichTextTests: XCTestCase {
    func testCodableRoundTripPreservesCanonicalAndUnknownAttributes() throws {
        let value = RichText(
            text: "Plan café",
            spans: [RichTextSpan(
                range: RichTextRange(location: 5, length: 4),
                attributes: RichTextAttributes(
                    styleNames: ["future-emphasis", RichTextStyle.bold.rawValue],
                    foregroundColorName: "future-color",
                    highlightColorName: RichTextColor.yellow.rawValue,
                    extensions: ["future-key": "future-value"]
                )
            )]
        )

        let decoded = try JSONDecoder().decode(
            RichText.self,
            from: JSONEncoder().encode(value)
        )

        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.spans[0].attributes.styleNames, ["bold", "future-emphasis"])
        XCTAssertEqual(decoded.spans[0].attributes.extensions["future-key"], "future-value")
    }

    func testDecodingNormalizesUntrustedOverlappingAndOversizedRanges() throws {
        let json = #"""
        {
          "representationVersion": 1,
          "text": "abc",
          "spans": [
            {
              "range": { "location": 0, "length": 9223372036854775807 },
              "attributes": {
                "styleNames": ["bold", "bold"],
                "extensions": {}
              }
            },
            {
              "range": { "location": 1, "length": 1 },
              "attributes": {
                "styleNames": ["italic"],
                "extensions": {}
              }
            }
          ]
        }
        """#

        let decoded = try JSONDecoder().decode(RichText.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.spans.map(\.range), [
            .init(location: 0, length: 1),
            .init(location: 1, length: 1),
            .init(location: 2, length: 1)
        ])
        XCTAssertEqual(decoded.spans[0].attributes.styleNames, ["bold"])
        XCTAssertEqual(decoded.spans[1].attributes.styles, [.bold, .italic])
        XCTAssertEqual(decoded.spans[2].attributes.styles, [.bold])
    }

    func testTaskCodableRequiresV3RichTextAndReadsV2AsPlainText() throws {
        var current = try Fixtures.task()
        let formatted = RichText(text: "Task", spans: [
            .init(
                range: .init(location: 0, length: 4),
                attributes: .init(styles: [.bold])
            )
        ])
        try current.editRichText(formatted, version: Fixtures.stamp(2))
        let encoded = try JSONEncoder().encode(current)
        XCTAssertEqual(try JSONDecoder().decode(Task.self, from: encoded).richText, formatted)

        var missingRichText = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        missingRichText.removeValue(forKey: "richText")
        XCTAssertThrowsError(try JSONDecoder().decode(
            Task.self,
            from: JSONSerialization.data(withJSONObject: missingRichText)
        ))

        let legacy = Task(
            id: current.id,
            noteID: current.noteID,
            createdAt: current.createdAt,
            text: current.text,
            textVersion: current.textVersion,
            completion: current.completion,
            completionVersion: current.completionVersion,
            orderToken: current.orderToken,
            orderVersion: current.orderVersion,
            lifecycle: current.lifecycle,
            lifecycleVersion: current.lifecycleVersion,
            schemaVersion: 2
        )
        let decodedLegacy = try JSONDecoder().decode(
            Task.self,
            from: JSONEncoder().encode(legacy)
        )
        XCTAssertEqual(decodedLegacy.richText, RichText(text: current.text))
    }

    func testOverlapsNormalizeIntoNonOverlappingComposedSpans() {
        let value = RichText(text: "abcdef", spans: [
            .init(
                range: .init(location: 0, length: 4),
                attributes: .init(styles: [.bold])
            ),
            .init(
                range: .init(location: 2, length: 4),
                attributes: .init(styles: [.italic], foregroundColor: .blue)
            )
        ])

        XCTAssertEqual(value.spans.map(\.range), [
            .init(location: 0, length: 2),
            .init(location: 2, length: 2),
            .init(location: 4, length: 2)
        ])
        XCTAssertEqual(value.spans[0].attributes.styles, [.bold])
        XCTAssertEqual(value.spans[1].attributes.styles, [.bold, .italic])
        XCTAssertEqual(value.spans[2].attributes.styles, [.italic])
        XCTAssertEqual(value.spans[1].attributes.foregroundColor, .blue)
    }

    func testFormattingUsesSelectionOrCaretWordAndTogglesDeterministically() {
        let plain = RichText(text: "one two")
        let selected = plain.applying(
            .toggle(.underline),
            to: .init(location: 0, length: 3)
        )
        XCTAssertEqual(selected.spans[0].range, .init(location: 0, length: 3))

        let caretWord = selected.applying(
            .toggle(.italic),
            to: .init(location: 7, length: 0)
        )
        XCTAssertEqual(caretWord.spans.last?.range, .init(location: 4, length: 3))
        XCTAssertTrue(caretWord.spans.last?.attributes.contains(.italic) == true)

        XCTAssertEqual(
            selected.applying(.toggle(.underline), to: .init(location: 0, length: 3)),
            plain
        )
        let trailingCaret = plain.applying(
            .toggle(.bold),
            to: .init(location: 3, length: 0)
        )
        XCTAssertEqual(trailingCaret.spans.first?.range, .init(location: 0, length: 3))
    }

    func testFormattingRangeCannotSplitEmojiGrapheme() {
        let value = RichText(text: "A👩🏽‍💻B").applying(
            .highlight(.yellow),
            to: .init(location: 2, length: 1)
        )

        XCTAssertEqual(value.spans.count, 1)
        XCTAssertEqual(value.spans[0].range.location, 1)
        XCTAssertGreaterThan(value.spans[0].range.length, 1)
    }

    func testTrimmingPreservesAndRebasesFormatting() {
        let value = RichText(text: "  plan now \n", spans: [
            .init(
                range: .init(location: 1, length: 7),
                attributes: .init(styles: [.bold])
            )
        ])

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(trimmed.text, "plan now")
        XCTAssertEqual(trimmed.spans, [
            .init(
                range: .init(location: 0, length: 6),
                attributes: .init(styles: [.bold])
            )
        ])
    }
}
