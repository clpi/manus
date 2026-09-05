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

The archive is complete. Recovery from the original project inputs reproduced
the exact container identity already pinned in manifest.json, including both
names of the duplicate source. The former truncated blob remains in Git history;
it is never accepted as a complete corpus.

The authority gate checks the compressed identity, complete gzip stream, exact
member roster and every member's bytes. Its complete/corrupt classifier retains
positive and damaged-input controls. Archive acceptance is research integrity,
not compiler, self-host or performance acceptance.

To verify reproducibility or restore the container from original files on disk:

    ./tools/node/dev/rebuild-pass2-archive.sh --check /path/to/pass-2/sources
    ./tools/node/dev/rebuild-pass2-archive.sh /path/to/pass-2/sources
    sh gate/authority.sh

The rebuild script verifies each source's name, byte count and SHA-256, then
creates deterministic USTAR and gzip bytes with fixed metadata. It validates the
complete container against the manifest before atomically replacing the archive.
Missing or damaged input, duplicate manifest keys and a container mismatch leave
the prior archive unchanged. The --check option performs the same verification
without writing. The authority gate exercises successful rebuilding and those
refusal paths in an isolated temporary fixture.

## Integration rule

Research becomes active implementation only when it is reconciled through the one semantic graph, has a named consumer, preserves occurrence/value lineage, carries executable controls, and meets performance monotonicity: substantially better when a performance mechanism lands, or no regression where no performance change is claimed. Unimplemented findings remain explicit gaps; they are never deleted merely because an authority document is consolidated.
