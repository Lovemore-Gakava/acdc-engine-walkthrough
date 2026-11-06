# Two experiments: change one thing, run the same engine steps, compare.
#   Rscript experiments.R
# WALKTHROUGH.md, "Try it", explains what each one shows. The app (app.R) offers these and more.

source(file.path("R", "setup.R"))
source(file.path("R", "steps.R"))
adlb <- as.data.frame(nanoparquet::read_parquet(adlb_path))

run <- function(label, changes) {
  s <- utils::modifyList(DEFAULT_SETTINGS, changes)
  r <- engine_steps(order_adlb(adlb, s$order), s)
  cat(sprintf("%-46s %6.3f (SE %.3f)   covariate: %-20s   baselines differing from BASE: %d\n",
              label, r$contrast$estimate, r$contrast$SE, r$roles[["covariate"]], r$n_differ))
}

run("As captured", list())
# 1. Leave the covariate at the app's default: drop the step-8 override Measure -> BASE.
run("1. Covariate left at the app's default", list(covariate = "default"))
# 2. Same records, same values, different order: latest date first within each subject and parameter.
run("2. ADLB rows sorted latest date first", list(order = "latest"))

ref <- toriva_reference(adlb)
cat(sprintf("\nTORIVA's ADaM, for comparison: %.3f (SE %.3f)\n", ref$estimate, ref$SE))
