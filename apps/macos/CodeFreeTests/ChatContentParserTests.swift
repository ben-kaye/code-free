import XCTest
@testable import CodeFree

final class ChatContentParserTests: XCTestCase {
    func testPlainTextIsSingleMarkdownProse() {
        let blocks = ChatContentParser.parse("hello world")
        XCTAssertEqual(blocks.count, 1)
        guard case .prose(let inlines) = blocks[0] else {
            return XCTFail("expected prose")
        }
        XCTAssertEqual(inlines, [.markdown("hello world")])
    }

    func testFencedCodeBlock() {
        let src = """
        before
        ```swift
        let x = 1
        ```
        after
        """
        let blocks = ChatContentParser.parse(src)
        XCTAssertEqual(blocks.count, 3)
        guard case .prose = blocks[0] else { return XCTFail("prose before") }
        guard case .code(let lang, let body) = blocks[1] else {
            return XCTFail("code")
        }
        XCTAssertEqual(lang, "swift")
        XCTAssertEqual(body, "let x = 1")
        guard case .prose(let after) = blocks[2] else { return XCTFail("prose after") }
        XCTAssertEqual(after, [.markdown("after")])
    }

    func testUnclosedFenceTreatsRestAsCode() {
        let src = "```\npartial"
        let blocks = ChatContentParser.parse(src)
        XCTAssertEqual(blocks.count, 1)
        guard case .code(let lang, let body) = blocks[0] else {
            return XCTFail("code")
        }
        XCTAssertNil(lang)
        XCTAssertEqual(body, "partial")
    }

    func testDisplayMathDollars() {
        let blocks = ChatContentParser.parse("see $$E=mc^2$$ ok")
        XCTAssertEqual(blocks.count, 3)
        guard case .displayMath(let latex) = blocks[1] else {
            return XCTFail("display math")
        }
        XCTAssertEqual(latex, "E=mc^2")
    }

    func testDisplayMathBrackets() {
        let blocks = ChatContentParser.parse("\\[a+b\\]")
        XCTAssertEqual(blocks.count, 1)
        guard case .displayMath(let latex) = blocks[0] else {
            return XCTFail("display math")
        }
        XCTAssertEqual(latex, "a+b")
    }

    func testInlineMathDollars() {
        let blocks = ChatContentParser.parse("energy $E=mc^2$ yes")
        XCTAssertEqual(blocks.count, 1)
        guard case .prose(let inlines) = blocks[0] else {
            return XCTFail("prose")
        }
        XCTAssertEqual(
            inlines,
            [
                .markdown("energy "),
                .math("E=mc^2"),
                .markdown(" yes"),
            ]
        )
    }

    func testInlineMathParens() {
        let blocks = ChatContentParser.parse("sum \\(\\sum_i x_i\\) end")
        guard case .prose(let inlines) = blocks[0] else {
            return XCTFail("prose")
        }
        XCTAssertEqual(inlines[1], .math("\\sum_i x_i"))
    }

    func testDollarInsideCodeSpanNotMath() {
        let blocks = ChatContentParser.parse("use `$PATH` please")
        guard case .prose(let inlines) = blocks[0] else {
            return XCTFail("prose")
        }
        XCTAssertEqual(inlines.count, 1)
        guard case .markdown(let md) = inlines[0] else {
            return XCTFail("markdown only")
        }
        XCTAssertTrue(md.contains("`$PATH`"))
    }

    func testIncompleteInlineMathStaysLiteral() {
        let blocks = ChatContentParser.parse("price $5 and done")
        guard case .prose(let inlines) = blocks[0] else {
            return XCTFail("prose")
        }
        XCTAssertEqual(inlines, [.markdown("price $5 and done")])
    }

    func testMathSkippedInsideFencedCode() {
        let src = """
        ```
        $not_math$
        ```
        """
        let blocks = ChatContentParser.parse(src)
        XCTAssertEqual(blocks.count, 1)
        guard case .code(_, let body) = blocks[0] else {
            return XCTFail("code")
        }
        XCTAssertTrue(body.contains("$not_math$"))
    }

    func testIncompleteDisplayMathStaysInProse() {
        let blocks = ChatContentParser.parse("start $$\\frac{1}{ still open")
        XCTAssertEqual(blocks.count, 1)
        guard case .prose(let inlines) = blocks[0] else {
            return XCTFail("prose")
        }
        guard case .markdown(let md) = inlines[0] else {
            return XCTFail("markdown")
        }
        XCTAssertTrue(md.contains("$$"))
    }

    func testAttributedMarkdownBold() {
        let attr = ChatMarkdownStyle.attributed("**bold**")
        XCTAssertEqual(String(attr.characters), "bold")
    }

    func testAttributedMarkdownKeepsListMarkersAndNewlines() {
        // Regression: `.full` stripped block boundaries so Text smashed paragraphs/lists.
        let src = "Hello **world**.\n\n1. First item.\n2. Second item."
        let attr = ChatMarkdownStyle.attributed(src)
        let chars = String(attr.characters)
        XCTAssertTrue(chars.contains("1. First"), "list markers must remain in character buffer")
        XCTAssertTrue(chars.contains("2. Second"))
        XCTAssertFalse(chars.contains("world.1."), "must not smash paragraph into list")
        XCTAssertFalse(chars.contains("item.Second"), "must not smash list rows")
    }

    func testSplitProseUnitsParagraphsAndList() {
        let src = """
        Intro about **project**:

        **Code Free** is cool.

        That means:

        1. First ends.
        2. Second starts.
        3. Third.

        Closing para.
        """
        let units = ChatContentParser.splitProseUnits(src)
        XCTAssertEqual(
            units,
            [
                "Intro about **project**:",
                "**Code Free** is cool.",
                "That means:",
                "1. First ends.",
                "2. Second starts.",
                "3. Third.",
                "Closing para.",
            ]
        )
    }

    func testSplitProseUnitsSoftNewlineCollapsesToSpace() {
        let units = ChatContentParser.splitProseUnits("line one\nline two")
        XCTAssertEqual(units, ["line one line two"])
    }

    func testParseSplitsParagraphsIntoSeparateProseBlocks() {
        let blocks = ChatContentParser.parse("alpha\n\nbeta\n\n1. one\n2. two")
        XCTAssertEqual(blocks.count, 4)
        guard case .prose(let a) = blocks[0], case .markdown(let am) = a[0] else {
            return XCTFail("alpha")
        }
        guard case .prose(let b) = blocks[1], case .markdown(let bm) = b[0] else {
            return XCTFail("beta")
        }
        guard case .prose(let c) = blocks[2], case .markdown(let cm) = c[0] else {
            return XCTFail("1. one")
        }
        guard case .prose(let d) = blocks[3], case .markdown(let dm) = d[0] else {
            return XCTFail("2. two")
        }
        XCTAssertEqual(am, "alpha")
        XCTAssertEqual(bm, "beta")
        XCTAssertEqual(cm, "1. one")
        XCTAssertEqual(dm, "2. two")
    }

    func testInterestingMessageDoesNotSmashBlocks() {
        // Shape of the real “tell me something interesting!” log (paragraphs + tight list).
        let src = """
        Knowing. Here’s something cool about **your own project**:

        **Code Free treats the event log as the only source of truth** — not the stream.

        That means:

        1. The orchestrator appends events **before** they become “real.”
        2. The shell rebuilds by **replaying** (your `TranscriptReducer`).
        3. Restart mid-turn can resubscribe with `afterSeq`.

        That’s event sourcing for a local harness GUI.
        """
        let blocks = ChatContentParser.parse(src)
        let proseTexts: [String] = blocks.compactMap { block in
            guard case .prose(let inlines) = block else { return nil }
            return inlines.map { inline -> String in
                switch inline {
                case .markdown(let s): return s
                case .math(let s): return s
                }
            }.joined()
        }
        XCTAssertGreaterThanOrEqual(proseTexts.count, 6)
        XCTAssertTrue(proseTexts.contains { $0.hasPrefix("1. ") })
        XCTAssertTrue(proseTexts.contains { $0.hasPrefix("2. ") })
        XCTAssertTrue(proseTexts.contains { $0.hasPrefix("3. ") })
        // No single unit should contain smashed paragraph boundaries.
        for t in proseTexts {
            XCTAssertFalse(t.contains("truth** — not the stream.That means"))
            XCTAssertFalse(t.contains("real.”2. "))
            XCTAssertFalse(t.contains("TranscriptReducer`).3. "))
        }
    }

    func testParseCacheReturnsSameBlocks() {
        ChatParseCache.removeAll()
        let src = "hello $$E=mc^2$$ world"
        let a = ChatContentParser.parse(src)
        let b = ChatContentParser.parse(src)
        XCTAssertEqual(a, b)
    }

    func testStableMathIdSurvivesProseGrowth() {
        let early = ChatContentParser.parseIdentified("see $x$")
        let later = ChatContentParser.parseIdentified("see $x$ and more text after")

        let earlyMath = mathInlineIds(early)
        let laterMath = mathInlineIds(later)
        XCTAssertEqual(earlyMath, laterMath)
        XCTAssertEqual(earlyMath.count, 1)
    }

    func testDuplicateMathGetsDistinctIds() {
        let blocks = ChatContentParser.parseIdentified("$a$ and $a$")
        let ids = mathInlineIds(blocks)
        XCTAssertEqual(ids.count, 2)
        XCTAssertNotEqual(ids[0], ids[1])
    }

    func testDisplayMathIdStableWhenTrailingProseGrows() {
        let early = ChatContentParser.parseIdentified("$$E=mc^2$$")
        let later = ChatContentParser.parseIdentified("$$E=mc^2$$\nmore")
        let earlyDm = displayMathIds(early)
        let laterDm = displayMathIds(later)
        XCTAssertEqual(earlyDm, laterDm)
        XCTAssertEqual(earlyDm.count, 1)
    }

    private func mathInlineIds(_ blocks: [IdentifiedChatBlock]) -> [String] {
        blocks.flatMap { block -> [String] in
            guard case .prose(let inlines) = block.content else { return [] }
            return inlines.compactMap { part in
                if case .math = part.inline { return part.id }
                return nil
            }
        }
    }

    private func displayMathIds(_ blocks: [IdentifiedChatBlock]) -> [String] {
        blocks.compactMap { block in
            if case .displayMath = block.content { return block.id }
            return nil
        }
    }
}

final class MathBalanceTests: XCTestCase {
    func testBalancedSimple() {
        XCTAssertTrue(MathBalance.mayRender("E=mc^2"))
        XCTAssertTrue(MathBalance.mayRender("\\frac{1}{2}"))
    }

    func testUnbalancedBraces() {
        XCTAssertFalse(MathBalance.mayRender("\\frac{1}{"))
        XCTAssertFalse(MathBalance.mayRender("{a"))
    }

    func testEscapedBracesDoNotAffectDepth() {
        XCTAssertTrue(MathBalance.mayRender("\\{ a \\}"))
    }

    func testEnvironmentBalance() {
        XCTAssertTrue(MathBalance.mayRender("\\begin{matrix} a \\end{matrix}"))
        XCTAssertFalse(MathBalance.mayRender("\\begin{matrix} a"))
    }

    func testEmptyRejected() {
        XCTAssertFalse(MathBalance.mayRender(""))
        XCTAssertFalse(MathBalance.mayRender("   "))
    }

    func testTrailingBackslashIncomplete() {
        XCTAssertFalse(MathBalance.mayRender("x\\"))
    }
}
