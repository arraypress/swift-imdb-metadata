# Swift IMDbMetadata

IMDb without a key: search live, ratings offline.

```swift
import IMDbMetadata

let titles = try await Suggestion.titles("dune")
titles.first?.id       // "tt15239678"  — the id Plex, Radarr and Trakt key on
titles.first?.kind     // .movie

let people = try await Suggestion.names("chalamet")

try await RatingsIndex.update(at: file)          // 8.2 MB, once
let index = try RatingsIndex(at: file)
try index.rating(for: "tt0111161")               // 9.3, 3,232,723 votes
```

No key, no account, no scraping. Two endpoints IMDb publishes itself.

## Why this and not TMDB

`swift-tmdb-metadata` needs a free key and gives you cast, crew, budgets and
paging. This gives you neither — and gives you the two things it can't:

- **`tt…` ids.** Plex, Radarr, Sonarr, Trakt and Letterboxd all key on them.
  TMDB ids are a different namespace.
- **IMDb's own rating**, which is the number people actually quote, and which
  is not TMDB's.

Use both. They answer different questions.

## Search

The type-ahead endpoint imdb.com's own search box calls: eight results,
ranked by popularity, no paging and no filters. Titles, names, or both.

Passing a `tt…` id returns that exact title, which is how a lookup works here
without opening a page.

Two things measured against the live endpoint rather than assumed:

- **The single letter after `suggestion` is ignored.** `x`, `d` and `z` return
  identical results for the same query, so it is not a shard key. A literal
  `x` is used, which avoids inventing rules for a query starting with a digit,
  an accent or a quote.
- The fields are abbreviated — `l` title, `qid` type, `yr` year range, `s`
  stars — and `yr` is `"2008-"` for a running series, so the end year is
  optional even when the range is present.

## Ratings

IMDb publishes a daily dump. `title.ratings.tsv.gz` is **8.2 MB** and holds
about 1.7 million titles — small enough to keep, unlike `title.basics.tsv.gz`
at 216 MB, which is why this library does ratings and not full metadata.

The TSV is not kept. It becomes a sorted array of fixed-width records — a
32-bit numeric id, the rating × 10, the vote count — which is 16 MB and
answers a lookup with a binary search over an mmapped file. Measured: 0.07 s
to inflate, 0.45 s end to end, and no parsing at all at lookup time.

### The trap

**IMDb ships the file sorted lexicographically, not numerically.** `tt10466872`
comes before `tt9916880`, because `1` sorts before `9`. An earlier version of
this trusted the file's order and dropped every row that looked out of place —
which threw away **42% of the dataset**, silently, and made Dune's rating come
back as "no rating" rather than as an error. The records are sorted here, and
a test asserts that a lexicographic input survives intact.

A title with no rating is `nil`, not an error: IMDb does not publish one below
five votes.

Gzip is handled through Apple's `Compression` framework — no dependency, no
`Process`. An HTML error page served with a 200 is refused on the magic number
rather than inflating to an empty index.

## Licence and terms

This library is MIT. IMDb's datasets are theirs, published for personal and
non-commercial use — see <https://developer.imdb.com/non-commercial-datasets/>.
The suggestion endpoint is IMDb's own public one. Nothing here scrapes a page.

## Tested

21 tests, offline: recorded suggestion entries decoded (including a running
series, an unknown type and an `nm` id that must not become a title), the
lexicographic resort, a rating written as `10` rather than `10.0`, a missing
index reported as such rather than as "no ratings", and gzip refusing an HTML
error page.
