# Pass 2 research source archive

This directory preserves the complete 25-file Pass 2 research corpus supplied to the Idol project, byte-for-byte, including duplicated and superseded material. Nothing in the archive is silently rewritten, deduplicated, or promoted to law.

## Authority

- The project and language are **Idol**; canonical source uses `.id`.
- Current semantic authority lives on `clpi/idol` `main`, principally `docs/spec/constitution.md` and `docs/spec/law.md`.
- This archive is evidence and research provenance. It cannot override current law, current tests, or current measured implementation facts.
- Pass 2.28's Idsem rename recommendation is preserved as historical input but is **superseded** by the owner ruling restoring Idol. Its non-identity analysis remains available for reconciliation.
- Duplicate inputs are retained. In particular, Pass 2.10 and Pass 2.11 are byte-identical; both names remain in the archive because provenance is not content deduplication.

## Integrity

`manifest.json` records every original filename, byte count, SHA-256 digest, and disposition. `pass-2-source.tar.gz` is deterministic and contains the original files with their original filenames and exact bytes.

## Integration rule

Research becomes active implementation only when it is reconciled through the one semantic graph, has a named consumer, preserves occurrence/value lineage, carries executable controls, and meets performance monotonicity: substantially better when a performance mechanism lands, or no regression where no performance change is claimed. Unimplemented findings remain explicit gaps; they are never deleted merely because an authority document is consolidated.
