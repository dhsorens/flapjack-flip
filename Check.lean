import FlapjackFlip

/-!
`flip-check`: the test runner.

* `flip-check [DIR]` runs the decompiler on every test under `DIR` (default `tests`)
  and reports which pass. Exit code 0 iff all of them do.
* `flip-check build DIR` compiles each `DIR/*/source.pnk` to `image.fjimg`, records the
  binary's behaviour in `expected.txt`, and rejects programs that make poor tests.
* `flip-check run IMAGE` prints what an image does on each test input.
-/

open FlapjackFlip FlapjackFlip.Harness

/-- Test directories under `dir` that contain `file`, sorted. -/
def testDirs (dir : System.FilePath) (file : String) : IO (Array System.FilePath) := do
  let entries ← dir.readDir
  let dirs ← entries.filterM fun e => (e.path / file).pathExists
  return (dirs.map (·.path)).qsort (·.toString < ·.toString)

def describe (img : Image) : String :=
  String.intercalate "\n\n" <| inputs.map fun input =>
    let (o, steps) := run img input fuel
    s!"## input {hex input}\n{showObservation o}\n({steps} steps)"

/-- A test is only useful if the original terminates normally on every input and does
some I/O: otherwise "same behaviour" is too easy to satisfy. -/
def validate (img : Image) : Except String Unit := do
  for input in inputs do
    let (o, _) := run img input fuel
    unless showStatus o.status == showStatus (.halted .success) do
      throw s!"on input {hex input}: {showStatus o.status}"
    if o.events.isEmpty then throw s!"on input {hex input}: no FFI events"

def build (dir : System.FilePath) : IO UInt32 := do
  let mut bad := 0
  for t in ← testDirs dir "source.pnk" do
    let source ← IO.FS.readFile (t / "source.pnk")
    match compile source >>= fun img => (validate img).map fun _ => img with
    | .error e =>
      IO.eprintln s!"{t}: {e}"
      bad := bad + 1
    | .ok img =>
      IO.FS.writeFile (t / "image.fjimg") img.render
      IO.FS.writeFile (t / "expected.txt") (describe img ++ "\n")
      IO.println s!"built {t}"
  return if bad == 0 then 0 else 1

def check (dir : System.FilePath) : IO UInt32 := do
  let tests ← testDirs dir "image.fjimg"
  let mut passed := 0
  for t in tests do
    let source ← IO.FS.readFile (t / "source.pnk")
    let img ← Image.readFile (t / "image.fjimg")
    match checkCase decompile source img with
    | .ok () =>
      passed := passed + 1
      IO.println s!"PASS {t.fileName.getD ""}"
    | .error e => IO.println s!"FAIL {t.fileName.getD ""}: {e}"
  IO.println s!"\n{passed}/{tests.size} tests passed"
  return if passed == tests.size && tests.size > 0 then 0 else 1

def main (args : List String) : IO UInt32 := do
  match args with
  | [] => check "tests"
  | ["build", dir] => build dir
  | ["run", path] => IO.println (describe (← Image.readFile path)); return 0
  | [dir] => check dir
  | _ =>
    IO.eprintln "Usage: flip-check [DIR] | flip-check build DIR | flip-check run IMAGE"
    return 2
