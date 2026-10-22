# The FlapjackFlip challenge

Write a **formally verified decompiler** from RISC-V machine code back to
[Pancake](https://github.com/pirapira/flapjack) source, in Lean 4.

The binaries are produced by Flapjack, a verified Pancake compiler. Your decompiler
takes such a binary and returns Pancake source. When Flapjack compiles that source
again, the result must behave exactly like the original binary, on every input.
You prove that this holds in general, then show the decompiler works by passing the
tests.

Read [`docs/BACKGROUND.md`](docs/BACKGROUND.md) first. It explains the binaries, the
machine they run on, and what "behave exactly like" means.

## What you write

| File | What goes there |
|---|---|
| `FlapjackFlip/Decompile.lean` | `decompile : Image → Except String String` |
| `FlapjackFlip/Soundness.lean` | `theorem decompile_sound : DecompilerSound decompile` |

Add as many new modules under `FlapjackFlip/` as you like, as long as these two
import them. The starting `decompile` disassembles the binary and then gives up.
Giving up is always sound, so its proof is already complete. It passes no tests.

## What you must not change

The files listed in `FROZEN.sha256` make up the specification and the judge:
the image format, the compiler wrapper, the machine semantics, the theorem
statement, the test harness, the tests, the test generator, the build
configuration and the acceptance script. `scripts/accept.sh` refuses to run if any
of them has changed. If you think one of them is wrong, raise it rather than
editing around it.

## Success criteria

Your submission is accepted when **all** of the following hold. Run
`scripts/accept.sh` to check criteria 1–4 yourself. Criterion 5 is run by the
graders.

1. **It builds.** `lake build` succeeds with no errors and no warnings.

2. **It is proved.** `Acceptance.lean` type-checks:

   ```lean
   theorem acceptance : DecompilerSound decompile := decompile_sound
   ```

   and `#print axioms acceptance` lists only `propext`, `Classical.choice` and
   `Quot.sound`: no `sorry`, no new `axiom`, no `native_decide`. Flapjack's own
   compiler-correctness theorem (`nativeCLIOutput_correct`) needs nothing more, so
   neither should you.

3. **It works on the visible tests.** `lake exe flip-check` reports
   `120/120 tests passed`. For each test it:
   - runs `decompile` on `tests/*/image.fjimg`. The decompiler sees only the binary,
     never the source;
   - compiles the returned source with Flapjack. It must compile;
   - runs the original and the recompiled binary on riscv-zkvm against five fixed
     inputs (`FlapjackFlip.Harness.inputs`). Both must produce the identical FFI
     event trace and stop the same way;
   - checks the returned source has at most **4×** as many Pancake tokens as the
     test's original `source.pnk`.

4. **The frozen files are untouched.** `shasum -a 256 -c FROZEN.sha256` passes.
   Graders run it against their own copy of `FROZEN.sha256`.

5. **It works on programs it has never seen.** The graders generate a hidden set
   with `scripts/gen_tests.py SECRET_SEED 500 hidden`, build it with
   `lake exe flip-check build hidden`, and run `lake exe flip-check hidden`.
   **At least 95%** must pass, with criterion 3 applied to each test.

Criteria 1, 2 and 4 are pass/fail. Criterion 3 is pass/fail too. While you work,
the `n/120` count measures progress.

## Rules of thumb

- **Readable output is the point.** The token budget exists to rule out a
  "decompiler" that wraps the machine code in a RISC-V interpreter written in
  Pancake. Such a program would be correct and useless. Variable names are free;
  aim for structured control flow and real function boundaries.
- **No memorisation.** Do not special-case the visible tests by hashing images or
  embedding their sources. Criterion 5 will catch it, and it misses the point.
- **The theorem is about every input binary**, not just ones Flapjack produced. You
  may return `.error` on anything you do not recognise. Soundness only constrains
  what you return as `.ok`.
- **Ask early.** If the specification seems to rule out something reasonable, or
  to allow something it shouldn't, say so.
