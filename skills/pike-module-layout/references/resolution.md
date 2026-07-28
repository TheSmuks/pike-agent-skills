# Module Resolution Reference

Verified against Pike 8.0.1116.

## Worked example

Layout:

```
mm/
├── main.pike
├── Prog.pike
├── Flat.pmod                 (file)
└── Deep.pmod/                (directory, no module.pmod)
    └── Inner.pmod/
        └── module.pmod
```

`main.pike`:

```pike
int main() {
  write("%s\n", Flat.who());        // Flat.pmod file → module
  write("%s\n", Deep.Inner.who());  // nested dirs → dotted namespace
  write("%s\n", Prog()->greet());   // .pike → instantiable program
  return 0;
}
```

Run:

```bash
pike -M mm mm/main.pike
```

All three resolve. Note `Deep.pmod/` has no `module.pmod` and is still traversable —
it exists purely to hold `Inner.pmod`.

## Resolution order

1. Pike splits the dotted name on `.` — `MyLib.Net.Socket` → `MyLib`, `Net`, `Socket`.
2. The first component is looked up against each module path root in order.
3. At each root, both `<name>.pmod` (file) and `<name>.pmod/` (directory) are candidates.
4. Inside a directory module, the next component matches `<name>.pmod`, `<name>.pmod/`,
   or `<name>.pike`.
5. A `module.pmod` inside a directory contributes that directory's own symbols; they are
   merged with the entries the directory contains.

Consequence: `Foo.fn()` may come from `Foo.pmod/module.pmod`, and `Foo.Bar` from
`Foo.pmod/Bar.pike`, simultaneously.

## Name collisions

If both `Foo.pmod` (file) and `Foo.pmod/` (directory) exist at the same root, the layout
is ambiguous — do not rely on which wins. Pick one form.

A module earlier on the path shadows a later one with the same name. This is how a local
module can silently override a stdlib one. Diagnose with:

```bash
pike -e 'write("%O\n", Program.defined(SomeProgram));'
```

## Checking resolution without writing a program

```bash
# does it resolve?
pike -M ./lib -e 'write("%O\n", undefinedp(master()->resolv("MyLib.Net")));'   # 0 = yes

# what is in it?
pike -M ./lib -e 'write("%O\n", indices(MyLib.Net));'

# what paths are searched?
pike -e 'write("%O\n", master()->pike_module_path);'
```

## Common failures

| Symptom | Cause |
|---------|-------|
| `module not found` | Module root not on the path — add `-M <dir>` |
| Resolves to the wrong implementation | Shadowing; check `Program.defined()` |
| `index does not exist` on a name you defined | Symbol is in a `.pike` (program) but accessed as a module namespace — instantiate it |
| Nested name fails, parent works | Intermediate directory missing the `.pmod` extension |
| Works from one directory, not another | Relying on the current directory instead of an explicit `-M` root |
