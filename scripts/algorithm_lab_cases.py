"""Developer-only differential fixtures. Independent brute-force oracles, small bounded inputs."""
import itertools
import random


def cases():
    rng = random.Random(1704)
    result = {}

    def add(lesson, name, a, tail, expected):
        tokens = [len(a), *a, *tail]
        result.setdefault(f"cpp.{lesson}.{name}", []).append(dict(input=" ".join(map(str, tokens)), output=str(expected)))

    def joined(values):
        return " ".join(map(str, values)) or "Empty"

    for _ in range(10):
        a = [rng.randint(-6, 6) for _ in range(rng.randint(0, 8))]
        n = len(a)
        ranges = [sorted([rng.randint(0, n), rng.randint(0, n)]) for _ in range(4)]
        tail = [len(ranges), *itertools.chain.from_iterable(ranges)]
        add("prefixlab", "build", a, [], " ".join(map(str, [0, *itertools.accumulate(a)])))
        add("prefixlab", "queries", a, tail, "".join(f"{sum(a[l:r])}\n" for l, r in ranges))
        add("prefixlab", "even", a, tail, "".join(f"{sum(x % 2 == 0 for x in a[l:r])}\n" for l, r in ranges))
        add("prefixlab", "balance", a, [], next((i for i in range(n) if sum(a[:i]) == sum(a[i+1:])), -1))
        updates = [(l, r, rng.randint(-5, 5)) for l, r in ranges]
        changed = a.copy()
        for l, r, d in updates:
            for i in range(l, r): changed[i] += d
        add("prefixlab", "updates", a, [len(updates), *itertools.chain.from_iterable(updates)], joined(changed))
        k, threshold = rng.randint(1, 9), rng.randint(-10, 10)
        add("windowlab", "fixedcount", a, [k, threshold], sum(sum(a[i:i+k]) >= threshold for i in range(n-k+1)))
        if a:
            k = rng.randint(1, n)
            add("windowlab", "fixedmax", a, [k], max(sum(a[i:i+k]) for i in range(n-k+1)))
        else:
            add("windowlab", "fixedmax", [-5], [1], -5)
        nonnegative = [abs(x) for x in a]
        limit, target = rng.randint(0, 12), rng.randint(1, 15)
        segments = [(r-l, sum(nonnegative[l:r])) for l in range(n) for r in range(l+1, n+1)]
        add("windowlab", "longest", nonnegative, [limit], max((length for length, total in segments if total <= limit), default=0))
        add("windowlab", "shortest", nonnegative, [target], min((length for length, total in segments if total >= target), default=0))
        add("windowlab", "allcount", nonnegative, [limit], sum(total <= limit for _, total in segments))
        sorted_a = sorted(a)
        b = sorted(rng.randint(-6, 6) for _ in range(rng.randint(0, 8)))
        pair_sums = [a[i]+a[j] for i in range(n) for j in range(i+1, n)]
        add("pointerslab", "pair", sorted_a, [threshold], "Yes" if threshold in pair_sums else "No")
        add("pointerslab", "paircount", sorted_a, [threshold], sum(total <= threshold for total in pair_sums))
        add("pointerslab", "intersection", sorted_a, [len(b), *b], joined(sorted(set(a) & set(b))))
        add("pointerslab", "merge", sorted_a, [len(b), *b], joined(sorted(a+b)))
        add("pointerslab", "distinct", a, [], max((r-l for l in range(n) for r in range(l+1, n+1) if len(set(a[l:r])) == r-l), default=0))
        x = rng.randint(-8, 8)
        add("binarylab", "lower", sorted_a, [x], next((i for i, value in enumerate(sorted_a) if value >= x), n))
        add("binarylab", "last", sorted_a, [x], max((i for i, value in enumerate(sorted_a) if value <= x), default=-1))
        add("binarylab", "frequency", sorted_a, [x], a.count(x))
        bounds = [(rng.randint(-8, 8), rng.randint(-8, 8)) for _ in range(4)]
        add("binarylab", "valueinterval", sorted_a, [len(bounds), *itertools.chain.from_iterable(bounds)], "".join(f"{sum(lo <= value <= hi for value in a)}\n" for lo, hi in bounds))
        weights = [abs(x)+1 for x in a]
        days = rng.randint(1, 10)

        def min_days(capacity):
            # DP over every possible last-day boundary, independent of greedy reference code.
            dp = [0] + [n+1] * n
            for end in range(1, n+1):
                dp[end] = min((dp[start]+1 for start in range(end) if sum(weights[start:end]) <= capacity), default=n+1)
            return dp[n]

        answer = next((capacity for capacity in range(max(weights, default=0), sum(weights)+1) if min_days(capacity) <= days), 0)
        add("binarylab", "capacity", weights, [days], answer)
    return result
