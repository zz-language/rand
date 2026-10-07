# rand

Deterministic random numbers for ZZ. Pure ZZ, no dependencies.
Xoshiro128++ core, verified bit-for-bit against the reference algorithm.

## Install

```sh
zz add rand
```

Or by hand in `zz.toml`:

```toml
[dependencies.rand]
version = "^0.4.0"
```

Then `zz install`. Needs a toolchain with compound assignment +
AOT tuple boxing (dev line after `0.1.6`); older toolchains reject
the file at parse time.

## 30-second start

```zz
import rand

func main() {
    rng := rand.seed(42)
    v, rng := rand.u32(rng)
    println(v)   // 3389691633, every time
    // Method style is identical: value in, value + next state out.
    d6, rng := rng.randint(1, 7)
    println(d6)
    // One-off scripts: no state to thread (not reproducible).
    println(rand.quick_int(1, 7))
}
```

## The three rules

**1. Thread the state.** The generator is a plain value — every draw
hands back the next state alongside the value, so re-bind it on each
draw. Reusing the old state repeats the stream:

```zz
// Right: the stream advances.
v, rng := rng.randint(1, 7)

// Wrong: same value forever.
r := rng
a, _ := rand.randint(r, 1, 7)
b, _ := rand.randint(r, 1, 7)   // a == b, always
```

**2. Upper bounds are exclusive.** `randint(r, 1, 7)` is a d6 (1–6),
`below(r, 100)` is 0–99. Coming from Python: this matches
`range`/`randrange`, *not* `random.randint` (which is inclusive).

**3. Empty-prone draws return `Option`.** `pick`/`sample`/
`choices_weighted` give `.some(x)` or `.none` instead of raising:

```zz
p, rng := rng.pick(faces)
match p {
    .some(v) => println(v)
    .none => println("no faces!")
}

s, rng := rng.sample(faces, 3)
match s {
    .some(three) => println(three)
    .none => println("need 3 faces, have fewer")
}
```

**Selective imports keep their signatures.** `import rand(randint)`
lifts the name but not the semantics — it still needs the state:
`randint(rng, 1, 7)`, never `randint(1, 7)`. The bare-value shortcut
is `quick_int(1, 7)`.

## API reference

All draws take the state first and return `(value, next_state)`,
unless noted. Every draw below is also an `Rng` method — write
`rng.randint(1, 7)` or `rand.randint(rng, 1, 7)`, whichever reads
better at the call site.

### Seeds

```zz
rng := rand.seed(42)        // deterministic: same n, same stream, everywhere
rng := rand.auto_seed()     // live: OS entropy + wall clock (same-ms calls still differ)
```

Use `seed` for games with replay, tests, and anything you want to
reproduce. Use `auto_seed` for everything the user sees once.

### Integers

```zz
w, rng := rng.u32()         // word in [0, 2^32)
i, rng := rng.below(100)    // int in [0, 100), unbiased (no modulo bias)
d20, rng := rng.randint(1, 21)  // int in [1, 21): a d20
```

- `below(r, n)`: `n <= 1` draws `0` (there is nothing else it could be).
- `randint(r, lo, hi)`: `hi <= lo` draws `lo`.

### Floats

```zz
x, rng := rng.f64()                 // float in [0, 1): ZZ's random()
t, rng := rng.uniform(-1.0, 1.0)    // float in [a, b]; a > b mirrors the range
g, rng := rng.gauss(0.0, 1.0)       // normal draw, mean 0, stddev 1
```

- `uniform(r, a, a)` draws `a`; `gauss(r, mu, sigma)` with
  `sigma <= 0` draws `mu` exactly.
- Backend note: float *values* are identical everywhere, but
  *display* width differs (16 vs 17 digits) — pre-existing engine
  behavior, not this package.

### Coin flips and picks

```zz
b, rng := rng.boolean()             // true/false, top bit of a fresh word
p, rng := rng.pick(faces)           // random element, or .none when empty
```

### Sequences

```zz
c, rng := rng.choices(faces, 3)     // 3 draws with replacement (repeats expected)
s, rng := rng.sample(faces, 3)      // 3 distinct elements, or .none if k out of range
h, rng := rng.shuffle(faces)        // shuffled copy; the input is untouched
w, rng := rng.choices_weighted(faces, weights, 2)  // weighted draws, or .none on bad input
```

- `sample(r, xs, 0)` draws `.some([])`; `sample` returns `.none`
  when `k < 0` or `k > len`.
- `choices_weighted` returns `.none` on empty input, length
  mismatch, any negative weight, or all-zero weights.
  Zero-weight entries are never picked.

### Batch and script shortcuts

```zz
words, rng := rng.fill(200000)      // 200k raw words, ~12x faster than 200k u32 calls
ds, rng := rng.draw(1, 7, 4)        // 4d6 in one call: [4, 4, 1, 4]
println(rand.quick_int(1, 7))       // one bare int, self-seeding, not reproducible
```

- `fill(r, n)` / `draw(r, lo, hi, n)`: `n <= 0` yields `[]`.
- `draw` with `hi <= lo` yields `lo` n times without consuming
  state — exactly what looping `randint` would do.
- `quick_int` is for throwaway scripts only. Anything you test,
  replay, or debug wants an explicit `seed`/`auto_seed`.

## Seeding guide

| Situation | Use |
|---|---|
| Unit tests | `seed(fixed)` — deterministic, rerunnable |
| Game world / replay | `seed(slot)` — same seed replays the run |
| CLI one-shot, user-facing draw | `auto_seed()` |
| 5-line throwaway script | `quick_int(lo, hi)` |

## Testing code that uses rand

Seed it. Because streams are deterministic, the golden pattern is:
fixed seed in, exact stream out.

```zz
@test
func test_encounter_table() {
    r := rand.seed(7)
    // … drive your system off r, assert exact outcomes …
}
```

The library pins its own stream the same way
(`test_reference_stream` in `tests/rand_test.zz`), so a broken
algorithm fails loudly instead of drifting silently.

## Layout

```
src/rand.zz          the whole library (single file, no deps)
tests/rand_test.zz   45 checks: `cd tests && zz install && zz test`
tests/parity_dump.zz VM-vs-AOT stream dump (see below)
examples/demo.zz     every function runnable: `cd examples && zz install && zz run demo.zz`
bench/bench.zz       self-timing harness: `cd bench && zz install && zz run bench.zz -- N`
scripts/check-parity.sh  bit-identity across backends
```

## Correctness

`seed(42)` opens `3389691633, 594985917, 4134283714…` — the reference
stream, pinned word-for-word plus derived draws (`f64`, `below`,
`randint`, `uniform`, `gauss`) in `test_reference_stream`. Uniformity
is covered by chi-square smokes (`below` 10 buckets × 2000 draws,
`randint` 6 faces × 600 draws, ±4.5σ bounds) alongside shape checks
and determinism checks. Streams are bit-identical across backends
(`scripts/check-parity.sh` diffs VM vs AOT int-domain streams;
floats are excluded — backends render identical values at different
widths). `zz test` (from `tests/`) runs 45 checks.

## Speed (measured)

Method: `bench/bench.zz` (`cd bench && zz install`, then
`zz run bench.zz -- N` for VM or `zz build bench.zz -o bench_aot`
+ `./bin/bench_aot -- N` for AOT). Self-timed, N=200000 AOT /
N=500 VM, on x86_64 i3-4005U:

| op | AOT | VM |
|---|---|---|
| `u32` | ~1.6µs/draw | ~116µs/draw |
| `below` / `randint` / `boolean` | ~1.6µs/draw | ~200µs/draw |
| `f64` / `uniform` / `gauss` | ~1.7µs/draw | — |
| `pick` | ~2.1µs/draw | — |
| `fill(200k)` | 29ms (~0.15µs/word) | — |
| `draw(200k)` | 32ms (~0.16µs/draw) | — |
| `choices(200k)` | 55ms (~0.28µs/draw) | — |
| `choices_weighted(200k×100)` | 602ms (~3µs/draw, linear scan) | — |
| `shuffle(200k)` | 124ms (~0.6µs/elem) | — |
| `sample(100)` over 200k | ~8ms | — |

Notes:

- Every draw runs the xoshiro step inline on locals — no nested
  per-draw tuples anywhere. Single draws bottom out at the `u32`
  floor (~1.6µs); batch functions amortize further.
- Bulk `fill` beats a per-draw `u32` loop ~12x here (29ms vs 339ms):
  per-draw tuple allocation and dispatch dominate, not the xoshiro
  recurrence (a dozen integer ops).
- `gauss` sits at the `u32` floor plus its log/cos/sqrt tail — the
  transcendentals are the true cost, irreducible without changing
  the algorithm (and its pinned stream).
- `choices_weighted` scans weights linearly per draw; binary search
  would be O(log n) but changes float rounding and therefore the
  pinned stream — kept linear, documented.
- AOT runs ~35–70× faster than the debug VM on draws.

## Memory (measured)

Steady loops hold flat memory on the VM (~18B/draw noise over 200k
draws). On AOT builds, draw loops retain roughly half a kilobyte per
draw — an engine ownership gap in container appends (appended temps
are never released; the lowerer emits no releases at all), not this
package: plain int/string tuple churn stays flat in the same harness.
Tracked upstream (zaidejjo/zz#188); budget ~0.5KB per draw for long AOT
loops until then.

## Compatibility notes

- Needs compound assignment + AOT tuple boxing (dev line after 0.1.6);
  older toolchains reject the file at parse time.
- No dependencies, no I/O, no globals — safe to vendor anywhere.

## Changelog

- `0.4.0` — `Rng` method style for all draws, `draw` batch helper,
  `quick_int` one-shot; tests moved to `tests/` (45 checks);
  reference-stream pins + chi-square uniformity smokes;
  reproducible `bench/` harness with measured numbers; every draw
  inlined to the `u32` floor; VM-vs-AOT parity harness.
