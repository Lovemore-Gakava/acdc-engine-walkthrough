# Working in this repository

Rules for any session, human or AI, that edits it.

| Rule | Why |
| --- | --- |
| **Never edit `vendor/`.** Moving to a new engine commit means replacing the file, updating both checksums and regenerating `inputs/` | The point is to show what a pinned version of CDISC's engine does |
| **Never hand-edit `inputs/`.** Regenerate with `capture/`; experiment on a copy | The inputs are a record of what the app produced |
| **Every number in the docs is printed by a script in this repository.** Run it, then quote it | A number typed by hand drifts |
| **Run `Rscript walkthrough.R`, `Rscript experiments.R` and `Rscript check.R` before every commit** | They are what CI runs; each stops if the result moves |
| **Plain language; the docs say what a reader will see, not what the engine is meant to do** | The readers have mixed familiarity with the standards |
| **Our R sources ASCII-only; LF line endings everywhere** | A CRLF checkout breaks the engine and the checksum (`vendor/` and `inputs/` are kept as produced) |
