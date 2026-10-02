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
(`cd examples && zz install && zz run demo.zz`) for all twelve
functions in one runnable file.

## Functions

- `seed(n)` — deterministic state from one int.
- `auto_seed()` — live state from OS entropy + wall clock.
- `u32(r)` — word in `[0, 2^32)`.
- `below(r, n)` — int in `[0, n)`, unbiased (no modulo bias).
- `randint(r, lo, hi)` — int in `[lo, hi)`.
- `f64(r)` — float in `[0, 1)`.
- `uniform(r, a, b)` — float in `[a, b]` (`a > b` mirrors the range).
- `boolean(r)` — coin flip.
- `pick(r, xs)` — random element, or `.none` when empty.
- `choices(r, xs, k)` — k draws with replacement (repeats expected).
- `sample(r, xs, k)` — k distinct elements, or `.none` if out of range.
- `shuffle(r, xs)` — shuffled copy; the input is untouched.

Coming from Python: `below`/`randint` have an exclusive upper bound
(`randint(r, 1, 6)` is a d6, not 1–6 inclusive), `pick` returns
`Option` instead of raising, and `f64` is Python's `random()`.

## Correctness

`seed(42)` opens `3389691633, 594985917, 4134283714…` — the reference
stream. 6000 × `below(r, 6)` lands 959–1078 per face (all within
±3σ); `f64` averages 0.498 over 5000 draws. Streams are bit-identical
across backends. `zz test` runs 20 checks including these vectors.

## Speed (measured)

- `u32`: ~4.5µs/draw AOT (~90–260µs in the debug VM)
- `randint`: ~13µs/draw AOT
- `shuffle`: ~11µs/element AOT · `sample(100)`: ~2.7ms AOT

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
