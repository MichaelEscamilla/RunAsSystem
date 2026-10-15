# RunAsSystem (Michael Escamilla's tool)

Repo: https://github.com/MichaelEscamilla/RunAsSystem
GUI tool "Run As SYSTEM" that launches an installer/script in the SYSTEM
context. Three RUN AS modes: Session 0 (SYSTEM, hidden, no desktop — same as
ConfigMgr/Intune), Interactive (PsExec) (SYSTEM, UI visible), Current user
(elevated). Runs the target as a SCHEDULED TASK. Keeps a HISTORY list of past
runs. Shows the exact constructed COMMAND LINE + EXIT CODE/Stdout in RESULT.

## KEY FACT: it invokes scripts with `-File` (NOT -Command/-EncodedCommand)
For a .ps1 target + ArgumentList, it builds:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<script>.ps1" <ArgumentList>
=> The args are parsed by the Windows native tokenizer (CommandLineToArgvW),
NOT by PowerShell. Consequences for ArgumentList:
- Comma-array syntax `-Path 'a','b','c'` does NOT build an array (commas are
  literal under -File).
- SINGLE quotes are NOT honored by CommandLineToArgvW — only DOUBLE quotes
  group tokens. Single-quoted paths are treated literally.
- Spaces split tokens. A path like `...\Start Menu` breaks into pieces unless
  wrapped in DOUBLE quotes.
- Net effect with a comma+single-quote multi-path arg: the whole blob binds to
  the first named param and leftover fragments spill as positional args =>
  `PositionalParameterNotFound` (exit 1, "Incorrect function" Windows error).

This is NOT caused by the scheduled task or SYSTEM context — the same -File
command fails identically in a plain elevated console. The scheduled task just
runs the constructed line verbatim.

## How to pass MULTIPLE paths through RunAsSystem
Because it uses -File, you cannot build a PS array from the command line.
Options:
1. Pass a SINGLE path (use the deepest folder; `New-Item -Force` creates all
   parents). Wrap in DOUBLE quotes. Best for folder-create scripts like
   PatchMyPC-Set-Folder.ps1.
2. DONE 2026-10-13 (unreleased, no version bump yet): PS1 options row has
   "Passed as: -Command" (+ PowerShell 5.1/7 host). It emits `-Command "try { &
   '<script>' <args> } catch { Write-Error $_; exit 1 }; exit $LASTEXITCODE"`
   so comma-arrays work. Default stays -File. (try/catch needed: plain exit
   $LASTEXITCODE returns 0 on bad param/missing file; $? is false after exit N.)
3. Give the script param `[Parameter(ValueFromRemainingArguments)]` AND pass
   DOUBLE-quoted space-separated paths (fragile; prefer option 1).

## Also used as a repro tool
Interactive (PsExec) mode = SYSTEM injected into an interactive session; used to
reproduce the NoMachine "userprograms" installer crash (see
nomachine-installer-userprograms-crash.md). Session 0 mode reproduces the true
ConfigMgr/Intune device-context behavior.
