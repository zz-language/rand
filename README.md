# rand — deterministic random numbers for ZZ

Pure-ZZ random generation. No native plugins, no dependencies.
Core: **xoshiro128++** with 32-bit masked arithmetic (every step fits
`i64` with room to spare, so the overflow traps never fire).
Reference vectors verified bit-for-bit against the canonical algorithm.

## Use

Add the dependency, then import:

```toml
[dependencies.rand]
path = "path/to/rand"
```

```zz
import rand

func main() {
    rng := rand.seed(42)
    v, rng := rand.u32(rng)      // [0, 2^32)
    i, rng := rand.below(rng, 100) // [0, 100), unbiased
    x, rng := rand.f64(rng)        // [0, 1)
    b, rng := rand.boolean(rng)    // coin flip
    println(v)
}
```

Value semantics: the generator is a plain struct passed by value, so
every draw returns the updated state alongside the value — thread it
with `:=` re-binding (tuple `=` reassignment doesn't exist; just
re-bind each draw). Same seed, same stream, on every backend.

## API

| Function | Returns | Notes |
|---|---|---|
| `seed(n: int) -> Rng` | deterministic state | LCG-expanded; same seed, same stream |
| `auto_seed() -> Rng` | live state | OS entropy (`crypto.random_bytes`) mixed with wall clock |
| `u32(r: Rng) -> (int, Rng)` | word in `[0, 2^32)` | raw xoshiro128++ output |
| `below(r, n) -> (int, Rng)` | int in `[0, n)` | bitmask rejection — no modulo bias; `n <= 1` draws `0` |
| `f64(r) -> (float, Rng)` | float in `[0, 1)` | 32 bits of randomness over 2^32 |
| `boolean(r) -> (bool, Rng)` | coin flip | drawn from the word's top bit |
| `pick<T>(r, xs) -> (Option<T>, Rng)` | element or `.none` | `.none` for empty input |
| `shuffle<T>(r, xs) -> ([T], Rng)` | shuffled copy | input untouched (fresh storage) |

## Correctness

- `seed(42)` opens `3389691633, 594985917, 4134283714…` — the
  reference xoshiro128++ stream for the same expanded state.
- 6000 × `below(r, 6)`: buckets 959–1078 around 1000 (all within
  ±3σ); 5000 × `f64` mean 0.498 (σ ≈ 0.004).
- Streams are bit-identical across backends (200k-draw accumulators
  match exactly under `zz run` and `zz build`).

## Performance (measured, dev VM unless noted)

- `u32`: 200k draws in ~17.8s (VM) / ~1.0s (AOT binary)
- `below`: 200k draws in ~35.5s (VM) / ~2.3s (AOT binary)

Cost is per-draw tuple allocation and dispatch in the VM, not the
algorithm (a dozen integer ops). AOT is ~15–18× faster on the same
program.

## Notes

- `zz test` runs the suite in `tests/` (10 tests, incl. known-answer
  vectors). In-repo tests resolve via the self path-dependency
  (`[dependencies.rand] path = "."`); consumers use a normal path dep.
- Float *display* precision differs by backend (VM prints 16 digits,
  AOT 17) — values are identical, only rendering differs (pre-existing
  engine behavior, not this package).
