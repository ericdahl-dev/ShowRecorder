# One mono Broadcast WAV per Stem

Each Take is stored as one mono 24-bit Broadcast WAV file per USB Channel, named after its Source, rather than as one polyphonic file for all channels. Mono files drop straight into every DAW, can be renamed, deleted or handed off one at a time, and a corrupt file costs one channel instead of the whole Take. The cost is 18 files written in parallel, each with its own crash-safe header rewrites, and RF64 promotion per file. Boom Recorder offers polyphonic recording; we chose not to.

## Consequences

- Every Stem must stay aligned to the Take's timeline sample for sample. That is why Gaps and Dropouts are written as silence instead of being skipped.
- Markers are written into every Stem's cue chunk, not just one file.
