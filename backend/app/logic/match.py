"""Taste match between two shelves."""

from dataclasses import dataclass

K = 3  # smoothing: a tiny overlap of two tiny shelves must not score high


@dataclass(frozen=True)
class Match:
    both: int
    pct: int | None


def match_score(
    n_mine: int,
    n_theirs: int,
    common: list[tuple[float | None, float | None]],
    use_ratings: bool,
) -> Match:
    """Score two shelves.

    `common` holds (my best rating, their best rating) for each film on both
    shelves. A rating is None when its owner did not rate or does not share it.
    With `use_ratings` false, ratings are ignored. The score is 0 to 99 for
    shelves under about 600 shared films.
    """
    if not common:
        return Match(0, None)
    coverage = len(common) / (min(n_mine, n_theirs) + K)
    d = [abs(a - b) / 4.9 for a, b in common if use_ratings and a is not None and b is not None]
    harmony = 1 - 0.6 * sum(d) / (len(d) + 2)
    return Match(len(common), round(100 * coverage * harmony))
