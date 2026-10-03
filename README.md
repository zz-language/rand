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
}
```

The generator is a plain value: every draw hands back the next state
alongside the value, so re-bind it (`v, rng := …`) on each draw.
Same seed, same stream, on every backend. See `examples/demo.zz`
(`cd examples && zz install && zz run demo.zz`) for all fifteen
functions in one runnable file.

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

Coming from Python: upper bounds are exclusive (`randint(r, 1, 7)`
is a d6), `pick`/`sample` return `Option` instead of raising, and
`f64` is Python's `random()`.

## Correctness

`seed(42)` opens `3389691633, 594985917, 4134283714…` — the reference
stream. Ranges, weights, and shapes are covered by statistical smokes
(±3–5σ) plus determinism checks. Streams are bit-identical across
backends. `zz test` runs 28 checks including these vectors.

## Speed (measured)

- `u32`: ~4.5µs/draw AOT (~100–250µs in the debug VM)
- `randint`: ~13µs/draw AOT
- `shuffle`: ~11µs/element AOT · `sample(100)`: ~2.7ms AOT
- `fill(200k)`: 254ms vs 1122ms sequential — ~4.4x end-to-end

Cost is per-draw tuple allocation and dispatch, not the algorithm
(a dozen integer ops). AOT runs ~15–40× faster than the debug VM on
the same program.

## Memory (measured)

Steady loops hold flat memory on the VM (~18B/draw noise over 200k
draws). On AOT builds, draw loops retain roughly half a kilobyte per
draw — an engine ownership gap in container appends (appended temps
are never released; the lowerer emits no releases at all), not this
package: plain int/string tuple churn stays flat in the same harness.
Recorded for the upstream fix; budget ~0.5KB per draw for long AOT
loops until then.

## Notes

- Needs compound assignment + AOT tuple boxing (dev line after 0.1.6);
  older toolchains reject the file at parse time.
- Float *display* width differs by backend (16 vs 17 digits) — values
  are identical, only rendering differs (pre-existing engine behavior).
