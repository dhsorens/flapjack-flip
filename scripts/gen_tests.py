#!/usr/bin/env python3
"""Generate random Pancake test programs.

    scripts/gen_tests.py SEED COUNT OUTDIR

writes OUTDIR/gen_SEED_NNN/source.pnk for NNN < COUNT. Then
`lake exe flip-check build OUTDIR` compiles them and `lake exe flip-check OUTDIR`
runs the decompiler on them.

Every program reads input through `@in`, computes with arithmetic, branches,
bounded loops and calls, writes results through `@out`, and terminates. The same
seed always gives the same programs; the hidden test set is generated with a seed
the decompiler's authors do not know.
"""

import random
import sys
from pathlib import Path

BINOPS = ["+", "-", "*", "&", "|", "^"]
SHIFTS = ["<<", ">>>", ">>"]
CMPS = ["<", "<+", "==", "!=", ">=", ">=+", "<=", ">+"]


class Gen:
    def __init__(self, rng):
        self.rng = rng

    def literal(self):
        r = self.rng.random()
        if r < 0.6:
            return str(self.rng.randrange(0, 16))
        if r < 0.9:
            return str(self.rng.randrange(0, 1 << 16))
        return str(self.rng.randrange(0, 1 << 63))

    def expr(self, names, depth):
        r = self.rng.random()
        if depth == 0 or r < 0.3:
            if self.rng.random() < 0.75:
                return self.rng.choice(names)
            return self.literal()
        if r < 0.75:
            a = self.expr(names, depth - 1)
            b = self.expr(names, depth - 1)
            return f"({a} {self.rng.choice(BINOPS)} {b})"
        if r < 0.85:
            a = self.expr(names, depth - 1)
            return f"({a} {self.rng.choice(SHIFTS)} {self.rng.randrange(1, 64)})"
        if r < 0.95:
            return self.cond(names, depth - 1)
        return f"(ld8 (@base + {self.rng.randrange(0, 64)}))"

    def cond(self, names, depth):
        a = self.expr(names, depth)
        b = self.expr(names, depth)
        return f"({a} {self.rng.choice(CMPS)} {b})"

    def block(self, vars_, funcs, depth, indent, loops):
        lines = []
        for _ in range(self.rng.randrange(1, 4)):
            lines += self.stmt(vars_, funcs, depth, indent, loops)
        return lines

    def stmt(self, vars_, funcs, depth, indent, loops):
        pad = "  " * indent
        r = self.rng.random()
        target = self.rng.choice(vars_)
        if depth > 0 and r < 0.2:
            out = [f"{pad}if {self.cond(vars_, 2)} {{"]
            out += self.block(vars_, funcs, depth - 1, indent + 1, loops)
            if self.rng.random() < 0.5:
                out += [f"{pad}}} else {{"]
                out += self.block(vars_, funcs, depth - 1, indent + 1, loops)
            return out + [f"{pad}}}"]
        if depth > 0 and r < 0.35:
            counter = f"i{len(loops)}"
            out = [f"{pad}var 1 {counter} = 0;",
                   f"{pad}while {counter} < {self.rng.randrange(1, 9)} {{"]
            out += self.block(vars_, funcs, depth - 1, indent + 1, loops + [counter])
            out += [f"{pad}  {counter} = {counter} + 1;", f"{pad}}}"]
            return out
        if funcs and r < 0.5:
            name, arity = self.rng.choice(funcs)
            args = ", ".join(self.expr(vars_ + loops, 2) for _ in range(arity))
            return [f"{pad}{target} = {name}({args});"]
        if r < 0.6:
            return [f"{pad}st @base + 512, {self.expr(vars_ + loops, 2)};",
                    f"{pad}@out(0, 0, @base + 512, 8);"]
        if r < 0.65:
            return [f"{pad}@in(0, 0, @base + 520, 8);",
                    f"{pad}{target} = lds 1 (@base + 520);"]
        return [f"{pad}{target} = {self.expr(vars_ + loops, 3)};"]

    def function(self, name, arity):
        params = [f"p{k}" for k in range(arity)]
        lines = [f"fun 1 {name}({', '.join('1 ' + p for p in params)}) {{",
                 f"  var 1 t = {self.expr(params, 3)};"]
        lines += self.block(params + ["t"], [], 1, 1, [])
        lines += [f"  return {self.expr(params + ['t'], 2)};", "}"]
        return lines

    def program(self):
        funcs = [(f"f{k}", self.rng.randrange(1, 4)) for k in range(self.rng.randrange(0, 3))]
        lines = []
        for name, arity in funcs:
            lines += self.function(name, arity) + [""]
        vars_ = [f"v{k}" for k in range(4)]
        lines += ["fun 1 main() {", "  @in(0, 0, @base, 64);"]
        lines += [f"  var 1 {v} = lds 1 (@base + {8 * k});" for k, v in enumerate(vars_)]
        lines += self.block(vars_, funcs, 2, 1, [])
        lines += self.block(vars_, funcs, 2, 1, [])
        lines += [f"  st @base + {512 + 8 * k}, {v};" for k, v in enumerate(vars_)]
        lines += ["  @out(0, 0, @base + 512, 32);", "  return 0;", "}"]
        return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    seed, count, outdir = int(sys.argv[1]), int(sys.argv[2]), Path(sys.argv[3])
    for n in range(count):
        gen = Gen(random.Random(f"{seed}/{n}"))
        case = outdir / f"gen_{seed}_{n:03d}"
        case.mkdir(parents=True, exist_ok=True)
        (case / "source.pnk").write_text(f"// generated: seed {seed}, program {n}\n" + gen.program())


if __name__ == "__main__":
    main()
