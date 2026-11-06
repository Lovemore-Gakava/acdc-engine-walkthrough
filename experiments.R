# Two experiments: change one thing, run the same engine steps, compare.
#   Rscript experiments.R
# WALKTHROUGH.md, "Try it", explains what each one shows.

source(file.path("R", "setup.R"))

run_engine <- function(adlb, overrides) {
  spec <- read_input("spec"); mappings_all <- read_input("mapping"); derivations <- read_input("derivations")
  analysis <- spec$analyses[[1]]
  detected <- detect_store(adlb, mappings_all, spec)
  concepts <- quietly(ingest_to_concepts(adlb, detected$mappings, detected$domain_code,
                                         collect_used_concepts(spec, derivations),
                                         collect_qualified_bindings(spec, derivations)))
  derived <- quietly(apply_derivations(concepts, derivations, read_input("r_impls"),
                                       read_input("unit_conversions"), detected$mappings))
  cv <- quietly(build_concept_var_map(analysis$resolvedBindings, detected$mappings, overrides))
  for (role in names(analysis$analysisInputColumns)) cv$by_role[[role]] <- analysis$analysisInputColumns[[role]]
  cube <- quietly(execute_cube(derived, analysis$resolvedBindings, analysis$resolvedSlices, cv, overrides, character(0)))
  typed <- quietly(coerce_types(cube, analysis$resolvedBindings, cv$by_concept))
  res <- quiet_car(quietly(execute_method(typed, cv$by_role,
                                          parse_configs(analysis$configurationValues, read_input("method")),
                                          read_input("r_impl"))))
  b <- cube[["Measure.Result.Value__parameter_baseline"]]
  sprintf("%6.3f (SE %.3f)   covariate: %-20s   baselines differing from BASE: %d",
          res$contrasts$estimate, res$contrasts$SE, cv$by_role$covariate,
          sum(abs(b - cube$BASE) > 1e-9, na.rm = TRUE))
}

adlb <- as.data.frame(nanoparquet::read_parquet(adlb_path))
overrides <- read_input("overrides")

cat("As captured                                  ", run_engine(adlb, overrides), "\n")

# 1. Leave the covariate at the app's default: drop the step-8 override Measure -> BASE.
cat("1. Covariate left at the app's default        ", run_engine(adlb, overrides["Treatment"]), "\n")

# 2. Same records, same values, different order: latest date first within each subject and parameter.
reordered <- adlb[order(adlb$USUBJID, adlb$PARAMCD, -as.numeric(adlb$ADT)), ]
cat("2. ADLB rows sorted latest date first         ", run_engine(reordered, overrides), "\n")

cat("\nTORIVA's ADaM, for comparison: 1.305 (SE 1.607)\n")
