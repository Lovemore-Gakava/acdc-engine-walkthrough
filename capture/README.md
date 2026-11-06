# Capture: producing inputs/ from the app

Needed only to regenerate `inputs/`, for example after moving to a newer engine commit or a
different saved chain. The walkthrough itself needs none of this.

`capture.mjs` opens CDISC's app in headless Chrome, loads the saved chain, applies the settings
in `step8-settings.json`, and presses Execute in code. Two of the app's files are replaced as
they are served, and nothing on disk is changed:

- `js/utils/webr-engine.js` becomes `webr-recorder.js`, which records what the app hands to R
  instead of running R in the browser;
- `js/views/execute-analysis.js` is served as it is, plus one line that lets the script call
  the function behind the Execute button.

Everything up to the handover to R is the app's own code.

## Run it

You need Node 18 or later, a Chrome or Chromium, R with `nanoparquet` and `jsonlite`, and three
checkouts: cdisc-org/analysis-concepts at `739344c`, usdm-acdc-in-practice at
`quickstart-2026-11.2`, and torivumab-nsclc-301 at `a806630`.

```sh
cd capture && npm install && cd ..
Rscript capture/dataset-meta.R <toriva>/datasets/adam/adlb.parquet <toriva>/datasets/adam/adsl.parquet meta.json
node capture/capture.mjs --app <analysis-concepts> --factory <usdm-acdc-in-practice> \
     --meta meta.json --out inputs --chrome /path/to/chrome
Rscript check.R
```

`dataset-meta.R` gives the app what it would learn when the datasets are uploaded: their columns
and the distinct values of short character columns. `--chrome` can be left out if Playwright has
its own browser installed (`npx playwright install chromium`).

## What was checked

Run from a clean checkout of the app, this reproduces the committed `inputs/` exactly. Leaving
out the two visit settings that usdm-acdc-in-practice's guide also lists changes nothing,
because the saved chain already holds `C2D1`, so `step8-settings.json` has only the five that
matter.
