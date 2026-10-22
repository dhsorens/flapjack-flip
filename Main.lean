import FlapjackFlip

open FlapjackFlip

def usage : String :=
  "Usage: flapjack-flip [--disasm] IMAGE.fjimg\n" ++
  "Decompile a Flapjack RISC-V image to Pancake source on stdout.\n" ++
  "--disasm prints the decoded instructions instead."

def main (args : List String) : IO UInt32 := do
  match args with
  | ["--disasm", path] =>
    let img ← Image.readFile path
    for (i, k) in (disassemble img).zipIdx do
      let addr := codeBase.toNat + 4 * k
      IO.println s!"{addr}: {match i with | some i => repr i | none => "<undecodable>"}"
    return 0
  | [path] =>
    match decompile (← Image.readFile path) with
    | .ok src => IO.print src; return 0
    | .error e => IO.eprintln s!"flapjack-flip: {e}"; return 1
  | _ => IO.eprintln usage; return 2
