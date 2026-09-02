import Foundation
import Testing
@testable import SummonKit

private let fixedNow = Date(timeIntervalSince1970: 1_750_000_000) // 2025-06-15 in UTC

@Suite("Snippet placeholders")
struct SnippetTests {

    @Test("Plain text has no placeholders")
    func plainText() {
        let t = SnippetTemplate.parse("Thanks for reaching out!")
        #expect(!t.hasPlaceholders)
        #expect(t.fields.isEmpty)
        #expect(t.render().text == "Thanks for reaching out!")
    }

    @Test("A simple field is parsed and rendered from the supplied value")
    func simpleField() {
        let t = SnippetTemplate.parse("Hi {{first_name}}, thanks!")
        #expect(t.fields.map(\.name) == ["first_name"])
        #expect(t.render(values: ["first_name": "Hein"]).text == "Hi Hein, thanks!")
    }

    @Test("Field labels read as prose")
    func fieldLabels() {
        #expect(SnippetTemplate.parse("{{first_name}}").fields[0].label == "First name")
        #expect(SnippetTemplate.parse("{{invoiceNumber}}").fields[0].label == "Invoice number")
    }

    @Test("A default is used when no value is supplied, and overridden when one is")
    func defaults() {
        let t = SnippetTemplate.parse("Best regards,\n{{sender:Hein}}")
        #expect(t.fields[0].defaultValue == "Hein")
        #expect(t.render().text == "Best regards,\nHein")
        #expect(t.render(values: ["sender": "Sam"]).text == "Best regards,\nSam")
        // An empty value falls back to the default rather than inserting nothing.
        #expect(t.render(values: ["sender": ""]).text == "Best regards,\nHein")
    }

    @Test("Repeating a field reuses one value and asks for it once")
    func repeatedField() {
        let t = SnippetTemplate.parse("Dear {{name}}, ... Sincerely to {{name}}")
        #expect(t.fields.count == 1)
        #expect(t.render(values: ["name": "Acme"]).text == "Dear Acme, ... Sincerely to Acme")
    }

    @Test("Fields are ordered by first appearance")
    func fieldOrder() {
        let t = SnippetTemplate.parse("{{b}} {{a}} {{b}} {{c}}")
        #expect(t.fields.map(\.name) == ["b", "a", "c"])
    }

    @Test("The date token renders today, and offsets shift it")
    func dateToken() {
        let ctx = RenderContext(now: fixedNow, locale: Locale(identifier: "en_US"))
        let today = SnippetTemplate.parse("{{date}}").render(context: ctx).text
        let inThreeDays = SnippetTemplate.parse("{{date:+3d}}").render(context: ctx).text
        #expect(!today.isEmpty)
        #expect(today != inThreeDays)
    }

    @Test("Day offsets parse across units",
          arguments: [("+3d", 3), ("-1d", -1), ("+2w", 14), ("+1m", 30),
                      ("+1y", 365), ("5", 5), ("garbage", nil as Int?)])
    func dayOffsets(raw: String, expected: Int?) {
        #expect(SnippetTemplate.parseDayOffset(raw) == expected)
    }

    @Test("The clipboard token inserts the current clipboard")
    func clipboardToken() {
        let ctx = RenderContext(now: fixedNow, clipboard: "https://example.com/report")
        #expect(SnippetTemplate.parse("See {{clipboard}}").render(context: ctx).text
                == "See https://example.com/report")
    }

    @Test("The cursor token reports how far back the caret should sit")
    func cursorToken() {
        let r = SnippetTemplate.parse("Hi there,\n\n{{cursor}}\n\nKind regards").render()
        #expect(r.cursorOffsetFromEnd == 14) // "\n\nKind regards".count
        #expect(!r.text.contains("{{"))
    }

    @Test("Without a cursor token there is no caret offset")
    func noCursorToken() {
        #expect(SnippetTemplate.parse("no caret here").render().cursorOffsetFromEnd == nil)
    }

    @Test("Reserved names are never treated as fill-in fields")
    func reservedNamesNotFields() {
        let t = SnippetTemplate.parse("{{date}} {{time}} {{clipboard}} {{cursor}} {{real_field}}")
        #expect(t.fields.map(\.name) == ["real_field"])
        #expect(t.requiresInput)
    }

    @Test("An escaped brace pair renders literally")
    func escaping() {
        let t = SnippetTemplate.parse("Use \\{{name}} to insert a name")
        #expect(!t.requiresInput)
        #expect(t.render().text == "Use {{name}} to insert a name")
    }

    @Test("An unclosed placeholder is left as literal text")
    func unclosed() {
        let t = SnippetTemplate.parse("Broken {{name and more")
        #expect(!t.hasPlaceholders)
        #expect(t.render().text == "Broken {{name and more")
    }

    @Test("Whitespace inside the braces is tolerated")
    func whitespaceTolerated() {
        let t = SnippetTemplate.parse("{{  first_name  }}")
        #expect(t.fields.map(\.name) == ["first_name"])
    }

    @Test("An unfilled field with no default collapses to nothing")
    func unfilledCollapses() {
        #expect(SnippetTemplate.parse("A{{x}}B").render().text == "AB")
    }

    @Test("A realistic canned reply round-trips")
    func realisticReply() {
        let source = """
        Hi {{first_name}},

        Thanks for getting in touch about {{topic:your enquiry}}. \
        I've attached the details and will follow up on {{date:+3d}}.

        {{cursor}}

        Best,
        Hein
        """
        let t = SnippetTemplate.parse(source)
        #expect(t.fields.map(\.name) == ["first_name", "topic"])
        let out = t.render(values: ["first_name": "Marieke"],
                           context: RenderContext(now: fixedNow, locale: Locale(identifier: "en_GB")))
        #expect(out.text.contains("Hi Marieke,"))
        #expect(out.text.contains("your enquiry"))   // default applied
        #expect(!out.text.contains("{{"))
        #expect(out.cursorOffsetFromEnd == 12)       // "\n\nBest,\nHein".count
    }

    @Test("The convenience predicates agree with the parser")
    func predicates() {
        #expect(SnippetTemplate.containsPlaceholders("{{date}}"))
        #expect(!SnippetTemplate.requiresInput("{{date}}"))  // auto-filled, nothing to ask
        #expect(SnippetTemplate.requiresInput("{{name}}"))
        #expect(!SnippetTemplate.containsPlaceholders("nothing here"))
    }
}
