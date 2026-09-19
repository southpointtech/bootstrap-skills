---
name: tdd
description: Test-driven development. Use when the user wants to build features or fix bugs test-first, mentions "red-green-refactor", or wants integration tests.
---

# Test-Driven Development

TDD is the red → green loop. This skill is the reference that makes that loop produce tests worth keeping: what a good test is, where tests go, the anti-patterns, and the rules of the loop. Every section applies on every cycle: consult them before and during the loop, not after.

When exploring the codebase, read `CONTEXT.md` (if it exists) so test names and interface vocabulary match the project's domain language, and respect ADRs in the area you're touching.

## What a good test is

Tests verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't. A good test reads like a specification: "user can checkout with valid cart" tells you exactly what capability exists, and it survives refactors because it doesn't care about internal structure.

See [tests.md](.agents/skills/tdd/tests.md) for examples and [mocking.md](.agents/skills/tdd/mocking.md) for mocking guidelines.

## Seams: where tests go

A **seam** is the public boundary you test at: the interface where you observe behavior without reaching inside. Tests live at seams, never against internals.

**Test only at pre-agreed seams.** Before writing any test, write down the seams under test and confirm them with the user. No test is written at an unconfirmed seam. You can't test everything, so agreeing the seams up front is how testing effort lands on the critical paths and complex logic instead of every edge case.

Ask: "What's the public interface, and which seams should we test?"

When the shape of that interface is itself in question (how deep the module is, where the seam belongs, what the interface should expose), read [deep-modules.md](.agents/skills/tdd/deep-modules.md) (small interface, deep implementation) and [interface-design.md](.agents/skills/tdd/interface-design.md) (interfaces designed for testability). They are references to consult, not a session to run.

## Anti-patterns

- **Implementation-coupled**: mocks internal collaborators, tests private methods, or verifies through a side channel (querying the database instead of using the interface). The tell: the test breaks when you refactor but behavior hasn't changed.
- **Tautological**: the assertion recomputes the expected value the way the code does (`expect(add(a, b)).toBe(a + b)`, a snapshot derived by hand the same way, a constant asserted equal to itself), so it passes by construction and can never disagree with the code. Expected values must come from an independent source of truth: a known-good literal, a worked example, the spec.
- **Horizontal slicing**: writing all tests first, then all implementation. Bulk tests verify _imagined_ behavior: you test the _shape_ of things rather than user-facing behavior, the tests go insensitive to real changes, and you commit to test structure before understanding the implementation. Work in **vertical slices** instead: one test → one implementation → repeat, each test a **tracer bullet** that responds to what the last cycle taught you.

## Rules of the loop

- **Red before green.** Write the failing test first, then only enough code to pass it. Don't anticipate future tests or add speculative features.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle.
- **Refactoring is not part of the loop.** It belongs to the review stage, not the red → green implementation cycle: the `/review-loop` that closes the slice runs `/code-review`, which looks for reuse and simplification, on its first turn of a `standard` slice. A slice declared `Review-Rigor: light` gets no such pass. A refactor you still want after the loop closes is a slice of its own that preserves behavior, and that kind of slice is the one `Review-Rigor: light` exists for.

## Close the slice

After green, before starting the next slice. This is NOT optional and you do NOT ask permission — you run it:

1. Check the diff size: `git --no-pager diff --stat` (or `git --no-pager diff <base>...HEAD --stat` on a feature branch). Generated files, vendored code, lockfiles and snapshots don't count toward the ~400-line guide. The ceiling was already spent when the slice OPENED, so a closing diff well over ~400 lines is **declared in the `Slice-Close:` trailer**, not split here — by now the pieces are interdependent and the review marker is anchored to this range. Record it so the next slice is planned smaller.
2. Commit. Multi-commit per slice is expected — one commit per green step. Declare the CLOSE of the slice in the last commit message with a `Slice-Close: <what closed>` trailer: that trailer is what fires the loop, so intermediate commits no longer pull a review run each. When the slice implements issues from `.scratch/`, cite each by its path in the trailer (`Slice-Close: .scratch/<feature>/issues/<NN>-<slug>.md — <what closed>`): that is how `/review-loop` knows which issues to mark `done`.
3. Run `/review-loop` on the unreviewed delta and iterate until it closes (zero medium/high findings, or its turn cap: 2, or 1 under `Review-Rigor: light`). Do NOT mark the slice done until the loop closes.
4. Only then start the next slice.

A RED-only commit (a failing test, no implementation) has nothing to review, and without the trailer it does not fire the loop. The hook still fires on a trailer-less commit once the unreviewed delta passes the ~400-line guide, so forgetting the trailer cannot leave a slice growing unreviewed; if that lands on a RED commit, the loop's pre-flight closes it without noise.
