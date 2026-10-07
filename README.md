# rand

Deterministic random numbers for ZZ. Pure ZZ, no dependencies.
Xoshiro128++ core, verified bit-for-bit against the reference algorithm.

```toml
[dependencies.rand]
path = "…"
# or: zz add rand
```

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

The generator is a plain value: every draw hands back the next state
alongside the value, so re-bind it (`v, rng := …`) on each draw.
Same seed, same stream, on every backend. See `examples/demo.zz`
(`cd examples && zz install && zz run demo.zz`) for all seventeen
functions in one runnable file. Tests live in `tests/`
(`cd tests && zz install && zz test`).

## Common mistakes

- Reusing the old state repeats the stream — always re-bind:
  `v, rng := rng.randint(1, 7)`, never `v, _ := …` in a loop.
- Upper bounds are exclusive: `randint(r, 1, 7)` is a d6 (1–6).
- `import rand(randint)` alone still needs an `Rng` first argument
  (`randint(rng, 1, 7)`); `quick_int(1, 7)` is the bare-value shortcut.

## Functions

- `seed(n)` — deterministic state from one int.
- `auto_seed()` — live state from OS entropy + wall clock.
- `u32(r)` — word in `[0, 2^32)`.
- `below(r, n)` — int in `[0, n)`, unbiased (no modulo bias).
- `randint(r, lo, hi)` — int in `[lo, hi)`.
- `f64(r)` — float in `[0, 1)`.
- `uniform(r, a, b)` — float in `[a, b]` (`a > b` mirrors the range).
- `gauss(r, mu, sigma)` — normal draw (Box-Muller).
- `boolean(r)` — coin flip.
- `pick(r, xs)` — random element, or `.none` when empty.
- `choices(r, xs, k)` — k draws with replacement.
- `choices_weighted(r, xs, ws, k)` — k weighted draws, or `.none` on
  bad input (empty, length mismatch, negative or all-zero weights).
- `sample(r, xs, k)` — k distinct elements, or `.none` if out of range.
- `shuffle(r, xs)` — shuffled copy; the input is untouched.
- `fill(r, n)` — n words in one call, ~4x faster than n draws
  (inlined recurrence, no per-draw tuple; verified bit-identical).
- `draw(r, lo, hi, n)` — n ints in `[lo, hi)` in one call.
- `quick_int(lo, hi)` — one-off bare int in `[lo, hi)` for scripts
  (self-seeding, not reproducible).

Every draw above also exists as an `Rng` method with identical
semantics: `v, rng := rng.randint(1, 7)`.

Coming from Python: upper bounds are exclusive (`randint(r, 1, 7)`
is a d6), `pick`/`sample` return `Option` instead of raising, and
`f64` is Python's `random()`.

## Correctness

`seed(42)` opens `3389691633, 594985917, 4134283714…` — the reference
stream, pinned word-for-word plus derived draws (`f64`, `below`,
`randint`, `uniform`, `gauss`) in `test_reference_stream`. Uniformity
is covered by chi-square smokes (`below` 10 buckets × 2000 draws,
`randint` 6 faces × 600 draws, ±4.5σ bounds) alongside shape checks
and determinism checks. Streams are bit-identical across backends
(`scripts/check-parity.sh` diffs VM vs AOT int-domain streams;
floats are excluded — backends render identical values at different
widths). `zz test` (from `tests/`) runs 44 checks.

## Speed (measured)

Method: `bench/bench.zz` (`cd bench && zz install`, then
`zz run bench.zz -- N` for VM or `zz build bench.zz -o bench_aot`
+ `./bin/bench_aot -- N` for AOT). Self-timed, N=200000 AOT /
N=500 VM, on x86_64 i3-4005U:

| op | AOT | VM |
|---|---|---|
| `u32` | ~1.7µs/draw | ~116µs/draw |
| `randint` | ~5.5µs/draw | ~200µs/draw |
| `fill(200k)` | 29ms (~0.15µs/word) | — |
| `draw(200k)` | ~1120ms (~5.6µs/draw) | — |
| `shuffle(200k)` | ~1126ms (~5.6µs/elem) | — |
| `sample(100)` over 200k | ~11ms | — |

Notes:

- Bulk `fill` beats a per-draw `u32` loop ~12x here (29ms vs 339ms):
  per-draw tuple allocation and dispatch dominate, not the xoshiro
  recurrence (a dozen integer ops).
- `draw` costs one `randint` per element (~5.6µs): it is a
  convenience batch, not a fast path — reach for `fill` (+ shift)
  when bulk words are what you need.
- AOT runs ~35–70× faster than the debug VM on draws.

## Memory (measured)

Steady loops hold flat memory on the VM (~18B/draw noise over 200k
draws). On AOT builds, draw loops retain roughly half a kilobyte per
draw — an engine ownership gap in container appends (appended temps
are never released; the lowerer emits no releases at all), not this
package: plain int/string tuple churn stays flat in the same harness.
Tracked upstream (zaidejjo/zz#188); budget ~0.5KB per draw for long AOT
loops until then.

## Notes

- Needs compound assignment + AOT tuple boxing (dev line after 0.1.6);
  older toolchains reject the file at parse time.
- Float *display* width differs by backend (16 vs 17 digits) — values
  are identical, only rendering differs (pre-existing engine behavior).

## Changelog

- `0.4.0` — `Rng` method style for all draws, `draw` batch helper,
  `quick_int` one-shot; tests moved to `tests/` (44 checks);
  reference-stream pins + chi-square uniformity smokes;
  reproducible `bench/` harness with measured numbers.
