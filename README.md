# acdc-engine-walkthrough

CDISC's AC/DC engine run step by step on TORIVA-LUNG 301: every input, decision and
intermediate result shown.

> **Status: draft, for a team sprint.** The engine comes from the CDISC Analysis Concepts
> project, which is still in development and not a published standard. This walkthrough shows
> what that draft does today, at a pinned commit.

## Why this exists

[usdm-acdc-quickstart](https://github.com/Lovemore-Gakava/usdm-acdc-quickstart) takes one
endpoint from a protocol to a result in about an hour. It shows that the chain runs. It does
not show how the number was made, and that is where the decisions are.

This repository opens the machinery up. It takes the same engine the quickstart's app uses,
calls its functions one at a time, and prints what each one does. Nothing is clicked and
nothing is hidden behind a screen. The inputs are files you can read, and the decisions that
shape the result are listed in one place.

## Use it in a browser

**https://lovemore-gakava.github.io/acdc-engine-walkthrough/**

The app runs the same engine in your browser, through webR: nothing to install. Change a
decision (the covariate, the population, the visit, the order of the records) and every step
runs again on all of TORIVA's ADLB. The first load takes a while, because R itself is
downloading; after that each change takes a few seconds.

The engine's result is checked in R before each publish; the browser version is checked by hand
(every setting against the numbers the scripts print), not automatically.

To run the app locally instead: `shiny::runApp()` from this folder (needs the `shiny` package
as well as the four below).

## Run it

You need R (4.0 or later) and four packages:

```r
install.packages(c("jsonlite", "nanoparquet", "car", "emmeans"))
```

Then, from this folder:

```sh
Rscript walkthrough.R     # the seven steps, about five seconds
Rscript experiments.R     # change one thing, see the result move
Rscript check.R           # the app's own single call gives the same answer
```

The first run downloads TORIVA's ADLB (1.8 MB) from its repository at the pinned commit and
checks it.

## What to read

1. [WALKTHROUGH.md](WALKTHROUGH.md): each step, what it prints, and what to notice.
2. [DECISIONS.md](DECISIONS.md): the twelve decisions behind the number, and where each is
   recorded. Five are typed on the app's last screen and saved nowhere.
3. [inputs/](inputs/README.md): the nine files the app hands the engine.

## What it shows

On one simple endpoint, ALT change from baseline at Cycle 2 Day 1:

- **The engine picks the baseline record by file order.** Most subjects have two ALT records in
  the baseline window. The engine keeps the first in the file; TORIVA's ADaM flags the last one
  on or before the day of first dose. In this dataset, sorting the file latest date first makes
  the two agree; nothing makes the engine follow the flag.
- **The model mixes two baselines.** The response uses the engine's baseline; the covariate uses
  ADaM's `BASE`, because of a setting typed on the last screen. For 293 of 427 subjects they
  differ. Either baseline used consistently gives close to TORIVA's result; mixing them makes
  the standard error 31 to 43% larger at every visit, and at two visits gives the estimate the
  other sign. At Cycle 2 Day 1: 1.276 (SE 2.215) against TORIVA's 1.305 (SE 1.607).
- **Settings that decide the result live nowhere.** The population, treatment variable,
  covariate, treatment filter and dataset are chosen from dropdowns before Execute. The saved
  chain still holds labels that match no data.

## What is pinned

| What | Where | Version |
| --- | --- | --- |
| The engine, `acdc_engine.R` | [cdisc-org/analysis-concepts](https://github.com/cdisc-org/analysis-concepts) | commit `739344c` ([vendor/](vendor/analysis-concepts/SOURCE.md)) |
| The study data, ADLB | [OpenTrialReporting/torivumab-nsclc-301](https://github.com/OpenTrialReporting/torivumab-nsclc-301) | commit `a806630` |
| The study definition and saved chain | [usdm-acdc-in-practice](https://github.com/Lovemore-Gakava/usdm-acdc-in-practice) | tag `quickstart-2026-11.2` |

The result is checked against the one usdm-acdc-in-practice recorded:
`endpoints/01-simple-lab-cfb/results.json`, run `p7_rerun_a806630`.

## What is in this repository

```
app.R                the app: the steps, with the decisions as settings
walkthrough.R        the seven steps, printed
experiments.R        two one-change experiments
check.R              the CDISC app's own call to the engine, for comparison
R/setup.R            pins, packages, data download, engine
R/steps.R            the engine's steps as one function, shared by the app and the scripts
inputs/              the nine inputs the app hands the engine, and the app's call (bootstrap.R)
vendor/              CDISC's engine, unmodified, with its licence
capture/             how inputs/ was produced from the app (needed only to regenerate it)
```

## Limits

- One endpoint, the simplest kind. Progression-free survival could not be authored in the app
  at all.
- How the app assembles the inputs (its JavaScript) is not shown; what it produced is.
- TORIVA-LUNG 301 is fully synthetic, and usdm-acdc-in-practice was built with AI assistance
  and has not been reviewed line by line (its `PROVENANCE.md`). The engine run here is the one
  check that does not depend on that: it reproduces the recorded numbers exactly.

## Related

- [endpoint-first](https://github.com/Lovemore-Gakava/endpoint-first): the proposed way of
  working this tests a piece of
- [usdm-acdc-quickstart](https://github.com/Lovemore-Gakava/usdm-acdc-quickstart): the same
  endpoint, quickly, through the app
- [usdm-acdc-in-practice](https://github.com/Lovemore-Gakava/usdm-acdc-in-practice): the worked
  example the inputs come from

## Licence

MIT, except `vendor/analysis-concepts/`, which keeps CDISC's MIT licence.
