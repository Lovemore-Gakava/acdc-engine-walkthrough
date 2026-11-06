# The walkthrough, step by step

`Rscript walkthrough.R` runs CDISC's analysis-concepts engine on one endpoint, one step at a
time, in the order the engine's own `acdc_execute()` runs them. This page explains each step
and what to notice. The output quoted here is what the script prints.

**The endpoint:** change from baseline in ALT (alanine aminotransferase) at Cycle 2 Day 1, in
the safety population, compared between the two arms by ANCOVA with baseline as a covariate.
TORIVA-LUNG 301's statistical analysis plan has no analysis of ALT. The endpoint was chosen in
[usdm-acdc-in-practice](https://github.com/Lovemore-Gakava/usdm-acdc-in-practice) because a
laboratory change from baseline is the simplest kind of endpoint, so it is a fair first test.

**What runs where:** the engine reads TORIVA's ADaM dataset ADLB, not its SDTM. It renames
ADLB's variables to concepts and re-derives the change from baseline from the analysis values,
even though ADLB already has one (`CHG`). That is how the app is set up for this endpoint, and
it is what lets the result be compared with TORIVA's own.

## Step 0: the decisions in the inputs

```
Slice 'endpoint':
  Parameter = Alanine Aminotransferase
  Population = Y on SAFFL
  Treatment = (no filter) on TRT01P
  Visit = C2D1
  AnalysisVisit = C2D1
Slice 'parameter_baseline':
  Parameter = Alanine Aminotransferase
  AnalysisVisit = Baseline
Overrides typed at the app's step 8: Measure -> BASE, Treatment -> TRT01P
```

A **slice** is a set of filters that picks records. The `endpoint` slice picks the records
analysed; the `parameter_baseline` slice picks the records that count as baseline.

Some of these values come from the chain saved in the app. Others were typed into dropdowns at
the app's last step and are saved nowhere. [DECISIONS.md](DECISIONS.md) lists each one and where
it lives.

## Step 1: read TORIVA's ADLB

```
133,855 records, 41 variables
```

TORIVA's laboratory analysis dataset, at the pinned commit, read straight from its parquet file.

## Step 2: ingest, where ADaM variables become concepts

```
Store detected: adam
Renamed, for example: USUBJID -> Subject, PARAM -> Parameter, AVISIT -> AnalysisVisit,
  AVAL -> Measure.Result.Value, CHG -> Change (12 concept columns in all)
```

Engine function: `ingest_to_concepts()`. The engine works on concept names, not ADaM names. A
mapping file (`inputs/mapping.json`) says which ADaM variable is which concept. From here on,
every step uses the concept names.

## Step 3: derive the change from baseline, using the concepts

```
Derivation: M.Subtraction (value minus the value in the slice 'parameter_baseline')
New columns: Measure.Result.Value__parameter_baseline, __col_T_CFB_ANCOVA_Change_0
The baseline slice is every ALT record with AnalysisVisit = Baseline. Where a subject
has more than one, the engine keeps the first (acdc_engine.R, line 1718).
Subject SITE001-0092, ALT records in the baseline window:
     VISIT        ADT AVAL ABLFL
 SCREENING 2022-06-11   12  <NA>
      C1D1 2022-07-05   30     Y
```

Engine function: `apply_derivations()`. The change is each ALT value minus the subject's
baseline value. The baseline is taken from the `parameter_baseline` slice: every ALT record in
the baseline window.

**This is where the first decision hides.** Most subjects have two records in that window, one
at screening and one on Cycle 1 Day 1, before the first dose. TORIVA's ADaM flags the later one
(`ABLFL = Y`). The engine has no setting for this. It keeps whichever record
comes first in the file (line 1718: `!duplicated(...)`). In ADLB that is the screening record.
For subject 0092 the engine's baseline is 12, and TORIVA's is 30.

## Step 4: bind, deciding which column plays which role

```
         role                      column
     response __col_T_CFB_ANCOVA_Change_0
    covariate                        BASE
 fixed_effect                      TRT01P
    partition                     Subject
   constraint   Parameter + AnalysisVisit
```

Engine function: `build_concept_var_map()`. The method (ANCOVA) has roles: a response, a
covariate, a treatment term. This step says which column fills each.

**This is where the second decision hides.** The response is the change the engine has just
derived, from its own baseline. The covariate is ADaM's `BASE`, TORIVA's flagged baseline,
because of the override typed at step 8 (`Measure -> BASE`). When a column named in an override
is already on every record, the engine skips its own baseline lookup for that role (around
line 1850). So the model's response and its covariate use two different baselines.

## Step 5: slice down to the analysis records

```
Filter: Parameter == Alanine Aminotransferase -> 11377 rows
Filter: SAFFL == Y -> 11377 rows
Filter: Visit == C2D1 -> 429 rows
Filter: AnalysisVisit == C2D1 -> 429 rows
429 records, one per subject
```

Engine function: `execute_cube()`. The `endpoint` slice's filters, applied in turn. Every
TORIVA subject with an ALT record is in the safety population, so that filter removes nothing.

## Step 6: fit the model the engine runs

```
lm(__col_T_CFB_ANCOVA_Change_0 ~ BASE + TRT01P)
(Placebo + Chemotherapy) - (Torivumab + Chemotherapy): 1.276 (SE 2.215), 95% CI -3.08 to 5.63, df 424
```

Engine functions: `coerce_types()` and `execute_method()`. The method's R code comes from the
inputs (`inputs/r_impl.json`): a linear model, then least-squares means and the difference
between arms with `emmeans`. Two subjects have no baseline value, so 427 of the 429 enter the model.

## Step 7: check the two baselines

```
293 of 427 subjects have different values for the two
TORIVA's ADaM (CHG ~ BASE + TRT01P, ANL01FL = Y): 1.305 (SE 1.607), n 427

Reproduces the recorded engine result: 1.276 (SE 2.215).
```

For 293 subjects, the baseline inside the response is not the baseline used as the covariate.
The engine's 1.276 therefore matches neither approach on its own: it is a mixture. The same
model fitted to TORIVA's own `CHG` and `BASE` gives 1.305.

The last line checks the result against the one recorded in usdm-acdc-in-practice
(`endpoints/01-simple-lab-cfb/results.json`, run `p7_rerun_a806630`). `Rscript check.R` also
runs the app's own single call to the engine (`inputs/bootstrap.R`) and confirms it gives the
same.

## Try it

`Rscript experiments.R` changes one thing at a time and runs the same steps:

```
As captured                                     1.276 (SE 2.215)   covariate: BASE                   baselines differing from BASE: 293
1. Covariate left at the app's default          0.538 (SE 1.554)   covariate: Measure.Result.Value   baselines differing from BASE: 293
2. ADLB rows sorted latest date first           1.305 (SE 1.607)   covariate: BASE                   baselines differing from BASE: 0
```

1. **Leave the covariate at the app's default.** Without the step-8 override, the covariate is
   the Cycle 2 Day 1 value itself, the response's own starting point. The model still runs and
   reports an answer, 0.538, with no warning.
2. **Change only the order of the rows.** Sort ADLB so each subject's latest record comes first.
   No value changes. The engine now keeps the Cycle 1 Day 1 record as baseline, every baseline
   matches TORIVA's, and the result is TORIVA's own: 1.305 (SE 1.607). **The engine's answer
   depends on the order of records in the file.**

The app ([README](README.md)) offers these two and more: other visits, the population, and the
saved chain's own values for the population and treatment filter, which stop the engine.

## What this walkthrough does not show

- **How the app builds these inputs.** That is done by the app's JavaScript
  (`execute-analysis.js` alone is about 2,800 lines). The
  inputs here are what it produced, captured by `capture/` and saved as files.
- **Three of the engine's steps.** `acdc_execute()` also enriches the data from other datasets,
  rolls up aggregations and builds a display preview. None of them does anything for this
  endpoint, so the walkthrough leaves them out. `check.R` runs the full function and gets the
  same answer.
- **Any other endpoint.** Progression-free survival could not be authored in the app at all
  (usdm-acdc-in-practice, endpoint 03).
