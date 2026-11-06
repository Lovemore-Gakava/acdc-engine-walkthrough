# ═══════════════════════════════════════════════════════════════
# AC/DC Execution Bootstrap
# Passes specification + implementation metadata to the engine
# ═══════════════════════════════════════════════════════════════

# Parse metadata from JSON
spec <- jsonlite::fromJSON(spec_json, simplifyVector = FALSE)
all_mappings <- jsonlite::fromJSON(mapping_json, simplifyVector = FALSE)
method_def <- jsonlite::fromJSON(method_json, simplifyVector = FALSE)
r_impl <- jsonlite::fromJSON(r_impl_json, simplifyVector = FALSE)

# Extract target store mappings (default: adam for backward compatibility)
target_store <- spec$targetStore
if (is.null(target_store)) target_store <- "adam"
mappings <- all_mappings[[target_store]]
if (is.null(mappings)) mappings <- all_mappings$adam

# Parse derivation chain and unit conversions (if present)
derivations <- if (exists("derivations_json")) jsonlite::fromJSON(derivations_json, simplifyVector = FALSE) else NULL
unit_conversions <- if (exists("unit_conversions_json")) jsonlite::fromJSON(unit_conversions_json, simplifyVector = FALSE) else NULL
r_impls <- if (exists("r_impls_json")) jsonlite::fromJSON(r_impls_json, simplifyVector = FALSE) else NULL
concept_categories <- if (exists("concept_categories_json")) jsonlite::fromJSON(concept_categories_json, simplifyVector = FALSE) else NULL

# User variable overrides (selected in UI)
overrides <- jsonlite::fromJSON(overrides_json, simplifyVector = FALSE)

# Load the analysis dataset
dataset <- get("adlb")
cat("Dataset: adlb,", nrow(dataset), "rows\n")

# Available datasets for dimension enrichment (all uploaded XPTs)
available_datasets <- c("adlb", "adsl")

# Presentation store for the Derived Data Preview panel (UI toggle).
presentation_store <- "adam"

# Execute using the generic AC/DC engine (capture console output for diagnostics)
console_log <- capture.output({
  result <- tryCatch(
    acdc_execute(spec, mappings, dataset, overrides, method_def, r_impl,
                 derivations, unit_conversions, r_impls, all_mappings, available_datasets,
                 concept_categories, presentation_store = presentation_store),
    error = function(e) list(engine_error = e$message)
  )
})
result$console <- paste(console_log, collapse = "\n")

# Return results as JSON
jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE)
