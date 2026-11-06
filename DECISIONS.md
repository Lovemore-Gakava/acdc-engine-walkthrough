# The decisions behind the number

Every choice that shapes the result 1.276, where it is recorded, and who would make it in a real
study. "Saved chain" is the file the app saves and loads
(usdm-acdc-in-practice, `endpoints/01-simple-lab-cfb/chain.json`). "Typed at step 8" means
chosen from a dropdown on the app's last screen. The app holds those in memory only, so they are
in no file except `capture/step8-settings.json` here, copied from usdm-acdc-in-practice's guide
(`docs/walkthrough.md`, step 8).

| Decision | Value used | Where it is recorded | Who would decide it in a real study |
| --- | --- | --- | --- |
| The endpoint | Change from baseline in ALT | USDM fragment and saved chain | Statistician, in the SAP. TORIVA's SAP has no ALT analysis; the worked example chose it |
| The method | ANCOVA, baseline as covariate | Saved chain (`T.CFB_ANCOVA`) | Statistician, in the SAP |
| The analysis visit | `AnalysisVisit = C2D1` | Saved chain | Statistician, in the SAP |
| The collected visit | `Visit = C2D1` | Saved chain | Statistician; without it, unscheduled draws that the visit windows assign to C2D1 also count |
| The population | `SAFFL = Y` | **Typed at step 8.** The saved chain says `SAF`, a label that matches no data | Statistician, in the SAP |
| The dataset | ADLB | **Typed at step 8** | Programmer, from the ADaM specification |
| The treatment variable in the model | `TRT01P` (the app's default is `TRTP`) | **Typed at step 8** | Statistician and programmer |
| The treatment filter | None: keep both arms | **Typed at step 8.** The saved chain says "Torivumab vs Placebo", a comparison label; left in place, it keeps one arm and the model fails | Nobody, today: a filter should not be there |
| The covariate | ADaM's `BASE` (the app's default is `AVAL`) | **Typed at step 8** | Statistician, in the SAP |
| The baseline record used in the change | The first record in the baseline window | **Nowhere: fixed in the engine's code** (`acdc_engine.R`, line 1718) | Statistician, in the SAP. TORIVA uses the last record before first dose (`ABLFL = Y`) |
| The direction of the comparison | Placebo minus torivumab | Nowhere: `emmeans::pairs()` takes the arms in alphabetical order | Statistician, in the SAP |
| The confidence level | 95% | The method's default (`inputs/method.json`, `alpha = 0.05`) | Statistician, in the SAP |

Five of these twelve are typed at the last step and saved nowhere. Two more are not settings at
all. Each one changes what is reported, or whether anything is. Run
`experiments.R` to see two of them change it.
