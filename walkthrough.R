# CDISC's AC/DC engine, one step at a time, on TORIVA-LUNG 301.
#
# Endpoint: change from baseline in ALT at Cycle 2 Day 1, safety population,
# ANCOVA with baseline as covariate. Run from the repository root:
#
#   Rscript walkthrough.R
#
# Each step calls the engine's own functions, in the order its acdc_execute()
# calls them, and prints what came out. WALKTHROUGH.md explains each step.

source(file.path("R", "setup.R"))
say <- function(...) cat(..., "\n", sep = "")
rule <- function(title) cat("\n== ", title, " ", strrep("=", max(0, 66 - nchar(title))), "\n", sep = "")

spec               <- read_input("spec")
all_mappings       <- read_input("mapping")
method_def         <- read_input("method")
r_impl             <- read_input("r_impl")
overrides          <- read_input("overrides")
derivations        <- read_input("derivations")
unit_conversions   <- read_input("unit_conversions")
r_impls            <- read_input("r_impls")
analysis           <- spec$analyses[[1]]

# ---------------------------------------------------------------------------
rule("Step 0  The decisions in the inputs")
say("Method: ", analysis$method$oid)
for (s in analysis$resolvedSlices) {
  vals <- unlist(s$resolvedValues); vars <- unlist(s$resolvedVariables)
  say("Slice '", s$name, "':")
  for (d in names(vals)) {
    v <- if (nzchar(vals[[d]])) vals[[d]] else "(no filter)"
    on <- if (!is.null(vars[d]) && !is.na(vars[d])) paste0(" on ", vars[[d]]) else ""
    say("  ", d, " = ", v, on)
  }
}
say("Overrides typed at the app's step 8: ",
    paste(names(overrides), unlist(overrides), sep = " -> ", collapse = ", "))

# ---------------------------------------------------------------------------
rule("Step 1  Read TORIVA's ADLB")
adlb <- as.data.frame(nanoparquet::read_parquet(adlb_path))
say(format(nrow(adlb), big.mark = ","), " records, ", ncol(adlb), " variables")

# ---------------------------------------------------------------------------
rule("Step 2  Ingest: ADaM variables become concepts")
detected <- detect_store(adlb, all_mappings, spec)
mappings <- detected$mappings
concepts <- quietly(ingest_to_concepts(
  adlb, mappings, detected$domain_code,
  collect_used_concepts(spec, derivations),
  collect_qualified_bindings(spec, derivations)))
renamed <- setdiff(colnames(concepts), colnames(adlb))
say("Store detected: ", detected$store)
say("Renamed, for example: USUBJID -> Subject, PARAM -> Parameter, AVISIT -> AnalysisVisit,")
say("  AVAL -> Measure.Result.Value, CHG -> Change (", length(renamed), " concept columns in all)")

# ---------------------------------------------------------------------------
rule("Step 3  Derive: change from baseline, by the concepts")
derived <- quietly(apply_derivations(concepts, derivations, r_impls, unit_conversions, mappings))
baseline_col <- "Measure.Result.Value__parameter_baseline"
change_col   <- analysis$analysisInputColumns$response
say("Derivation: ", derivations[[1]]$method$oid, " (value minus the value in the slice 'parameter_baseline')")
say("New columns: ", baseline_col, ", ", change_col)
say("The baseline slice is every ALT record with AnalysisVisit = Baseline. Where a subject")
say("has more than one, the engine keeps the first (acdc_engine.R, line 1718).")
one <- adlb[adlb$USUBJID == "CTX-NSCLC-301-SITE001-0092" &
            adlb$PARAM == "Alanine Aminotransferase" & adlb$AVISIT == "Baseline",
            c("VISIT", "ADT", "AVAL", "ABLFL")]
say("Subject SITE001-0092, ALT records in the baseline window:")
print(one, row.names = FALSE)

# ---------------------------------------------------------------------------
rule("Step 4  Bind: which column plays which role")
cv <- quietly(build_concept_var_map(analysis$resolvedBindings, mappings, overrides))
for (role in names(analysis$analysisInputColumns)) {
  cv$by_role[[role]] <- analysis$analysisInputColumns[[role]]
}
roles <- vapply(cv$by_role, paste, character(1), collapse = " + ")
print(data.frame(role = names(roles), column = unname(roles)), row.names = FALSE)
say("The covariate is ADaM's BASE because of the override, not the concept's baseline.")

# ---------------------------------------------------------------------------
rule("Step 5  Slice: down to the analysis records")
cube <- quietly(execute_cube(derived, analysis$resolvedBindings, analysis$resolvedSlices,
                             cv, overrides, character(0)))
filters <- grep("Filter:", engine_log, value = TRUE)
arrows <- function(x) gsub("<e2><86><92>|[^\\x01-\\x7f]+", "->", x, perl = TRUE, useBytes = TRUE)
cat(paste0(arrows(trimws(filters)), "\n"), sep = "")
say(nrow(cube), " records, one per subject")

# ---------------------------------------------------------------------------
rule("Step 6  Fit: the model the engine runs")
typed  <- quietly(coerce_types(cube, analysis$resolvedBindings, cv$by_concept))
result <- quiet_car(quietly(execute_method(typed, cv$by_role,
                                 parse_configs(analysis$configurationValues, method_def), r_impl)))
say(sprintf("lm(%s ~ %s + %s)", cv$by_role$response, cv$by_role$covariate, cv$by_role$fixed_effect))
ct <- result$contrasts
say(sprintf("%s: %.3f (SE %.3f), 95%% CI %.2f to %.2f, df %d",
            ct$Contrast, ct$estimate, ct$SE, ct$CI_lower, ct$CI_upper, as.integer(ct$df)))

# ---------------------------------------------------------------------------
rule("Step 7  Check: the two baselines in that model")
b_concept <- cube[[baseline_col]]; b_adam <- cube[["BASE"]]
both <- !is.na(b_concept) & !is.na(b_adam)
say("Response: ALT minus the concept's baseline (the first record in the window)")
say("Covariate: ADaM's BASE (the record TORIVA flags with ABLFL = Y)")
say(sum(both & abs(b_concept - b_adam) > 1e-9), " of ", sum(both),
    " subjects have different values for the two")

# The same model on TORIVA's own ADaM variables, for comparison.
ref <- adlb[adlb$PARAM == "Alanine Aminotransferase" & adlb$AVISIT == "C2D1" &
            adlb$SAFFL == "Y" & adlb$ANL01FL %in% "Y", ]
fit <- stats::lm(CHG ~ BASE + TRT01P, data = ref)
rc  <- as.data.frame(summary(pairs(emmeans::emmeans(fit, ~ TRT01P), adjust = "none")))
say(sprintf("TORIVA's ADaM (CHG ~ BASE + TRT01P, ANL01FL = Y): %.3f (SE %.3f), n %d",
            rc$estimate, rc$SE, stats::nobs(fit)))

# The result recorded by usdm-acdc-in-practice (endpoints/01-simple-lab-cfb/results.json).
if (abs(ct$estimate - 1.2757) > 1e-3 || abs(ct$SE - 2.2149) > 1e-3) {
  stop("The engine result no longer matches the recorded 1.2757 (SE 2.2149).", call. = FALSE)
}
say("\nReproduces the recorded engine result: 1.276 (SE 2.215).")
