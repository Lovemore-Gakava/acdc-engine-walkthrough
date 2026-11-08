# Two experiments: change one thing, run the same engine steps, compare.
#   Rscript experiments.R
# WALKTHROUGH.md, "Try it", explains what each one shows. The app (app.R) offers these and more.

source(file.path("R", "setup.R"))
source(file.path("R", "steps.R"))
adlb <- as.data.frame(nanoparquet::read_parquet(adlb_path))

run <- function(label, changes, expect) {
  s <- utils::modifyList(DEFAULT_SETTINGS, changes)
  r <- engine_steps(order_adlb(adlb, s$order), s)
  cat(sprintf("%-46s %6.3f (SE %.3f)   covariate: %-20s   baselines differing from BASE: %d\n",
              label, r$contrast$estimate, r$contrast$SE, r$roles[["covariate"]], r$n_differ))
  # Stop if a result moves: the docs quote these numbers.
  if (abs(r$contrast$estimate - expect[1]) > 1e-3 || abs(r$contrast$SE - expect[2]) > 1e-3) {
    stop(label, ": the result no longer matches the documented one.", call. = FALSE)
  }
}

run("As captured", list(), c(1.2757, 2.2149))
# 1. Leave the covariate at the app's default: drop the step-8 override Measure -> BASE.
run("1. Covariate left at the app's default", list(covariate = "default"), c(0.538, 1.554))
# 2. Same records, same values, different order: latest date first within each subject and parameter.
run("2. ADLB rows sorted latest date first", list(order = "latest"), c(1.3046, 1.6069))

# 3. The same records fitted three ways, at every visit the app offers: the captured (mixed)
#    model, the engine's baseline in both places, and ADaM's baseline in both places.
cat("\n3. Estimate (SE) at each visit: mixed | engine's baseline in both | ADaM's baseline in both\n")
for (v in c("C2D1", "C3D1", "C4D1", "C5D1", "C6D1")) {
  f <- three_fits(engine_steps(adlb, utils::modifyList(DEFAULT_SETTINGS, list(visit = v)))$cube)
  cat(sprintf("   %s   %s\n", v, paste(sprintf("%7.3f (%.3f)", f$estimate, f$SE), collapse = "   ")))
}

ref <- toriva_reference(adlb)
cat(sprintf("\nTORIVA's ADaM, for comparison: %.3f (SE %.3f)\n", ref$estimate, ref$SE))
