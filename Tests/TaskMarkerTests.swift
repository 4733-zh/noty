import Foundation

/// Checks that ☐/☑ task markers and Markdown task syntax convert on every line,
/// in both directions.
enum TaskMarkerTests {
    typealias Check = (Bool, String) -> Void

    static func run(check: Check) {
        testEveryTaskLineConverts(check)
        testMidLineMarkerIsNotATask(check)
        testTaskRoundTrip(check)
        testLineStatusRoundTrip(check)
    }

    private static func testEveryTaskLineConverts(_ check: Check) {
        let markdown = """
        - [ ] first
        - [x] second
          - [ ] indented third
        not a task
        """
        let expected = """
        \(Tasks.openPrefix)first
        \(Tasks.donePrefix)second
          \(Tasks.openPrefix)indented third
        not a task
        """
        check(Tasks.fromMarkdown(markdown) == expected,
              "every markdown task line must convert, not only the first")
    }

    private static func testMidLineMarkerIsNotATask(_ check: Check) {
        let body = "the \(Tasks.open) glyph used mid-sentence"
        check(Tasks.toMarkdown(body) == body,
              "a marker in the middle of a line is text, not a task")
    }

    private static func testTaskRoundTrip(_ check: Check) {
        let body = """
        \(Tasks.openPrefix)open
        \(Tasks.donePrefix)done
        a plain line
          \(Tasks.openPrefix)nested
        """
        check(Tasks.fromMarkdown(Tasks.toMarkdown(body)) == body,
              "tasks must survive a markdown round trip unchanged")
    }

    private static func testLineStatusRoundTrip(_ check: Check) {
        let status = NoteStatus(id: "test-status", name: "Testing", colorHex: "F59E0B")
        let source = "\(Tasks.openPrefix)Check the interface\n"
        let tagged = LineStatus.replacing(in: source, with: status)
        check(LineStatus.statusID(in: tagged) == status.id,
              "a status must be associated with its own checklist line")
        check(tagged.contains("〔Testing〕") && tagged.contains("<noty-status:test-status>"),
              "a line status must carry a readable label and stable id")
        check(LineStatus.stripping(from: tagged) == source,
              "list and title summaries must omit hidden status source text")
        let renamed = NoteStatus(id: status.id, name: "Ready", colorHex: status.colorHex)
        let renamedLine = LineStatus.updatingLabel(for: renamed, in: tagged)
        check(renamedLine.contains("〔Ready〕") && LineStatus.statusID(in: renamedLine) == status.id,
              "renaming a status must update its visible line label without changing its id")
        check(LineStatus.replacing(in: tagged, with: nil) == source,
              "clearing a line status must restore the original line")
    }
}
