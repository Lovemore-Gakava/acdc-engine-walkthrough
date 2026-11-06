# Check: the step-by-step run gives what the app's own single call gives.
# Runs inputs/bootstrap.R, the code the app sends to the engine, unchanged.
#   Rscript check.R

source(file.path("R", "setup.R"))
for (name in c("spec", "mapping", "method", "r_impl", "overrides", "derivations",
               "unit_conversions", "r_impls", "concept_categories")) {
  assign(paste0(name, "_json"),
         paste(readLines(file.path("inputs", paste0(name, ".json")), warn = FALSE), collapse = "\n"))
}
adlb <- as.data.frame(nanoparquet::read_parquet(adlb_path))
whole <- jsonlite::fromJSON(quiet_car(eval(parse(file.path("inputs", "bootstrap.R")))))
if (!is.null(whole$engine_error)) stop("engine error: ", whole$engine_error, call. = FALSE)
ct <- whole$contrasts
cat(sprintf("acdc_execute(), as the app calls it: %.4f (SE %.4f)\n", ct$estimate, ct$SE))
stopifnot(abs(ct$estimate - 1.2757) < 1e-3, abs(ct$SE - 2.2149) < 1e-3)
cat("Matches the recorded result and the step-by-step run.\n")
