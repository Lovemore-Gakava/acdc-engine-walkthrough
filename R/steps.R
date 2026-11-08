# The engine's steps as one function, so the app and the scripts run the same code.
# Needs R/setup.R sourced first (the engine, read_input(), quietly(), quiet_car()).

# What can be changed, and the value in the captured inputs.
DEFAULT_SETTINGS <- list(
  order      = "file",    # "file": ADLB as TORIVA ships it; "latest": latest date first per subject
  covariate  = "BASE",    # "BASE": the step-8 override; "default": no override, the app's default
  population = "SAFFL",   # "SAFFL", "ITTFL", or "saved": the saved chain's value, SAF, on the app's
                          #   default population variable, ITTFL (the chain holds only the value)
  visit      = "C2D1",    # the analysis visit, and the collected visit with it
  treatment  = "none"     # "none": no filter (typed at step 8); "saved": the saved chain's label,
                          #   on TRT01P, the variable typed at step 8
)

# Apply the settings to a copy of the captured inputs.
apply_settings <- function(settings) {
  spec <- read_input("spec"); overrides <- read_input("overrides")
  ep <- spec$analyses[[1]]$resolvedSlices[[1]]
  stopifnot(identical(ep$name, "endpoint"))
  if (settings$covariate == "default") overrides$Measure <- NULL
  if (settings$population == "ITTFL") {
    ep$resolvedVariables$Population <- "ITTFL"; ep$resolvedValues$Population <- "Y"
  } else if (settings$population == "saved") {
    ep$resolvedVariables$Population <- "ITTFL"; ep$resolvedValues$Population <- "SAF"
  }
  ep$resolvedValues$Visit <- settings$visit
  ep$resolvedValues$AnalysisVisit <- settings$visit
  if (settings$treatment == "saved") ep$resolvedValues$Treatment <- "Torivumab vs Placebo"
  spec$analyses[[1]]$resolvedSlices[[1]] <- ep
  list(spec = spec, overrides = overrides)
}

# ADLB in the chosen order. Same records, same values.
order_adlb <- function(adlb, order) {
  if (order == "latest") adlb[order(adlb$USUBJID, adlb$PARAMCD, -as.numeric(adlb$ADT)), ] else adlb
}

# Steps 2 and 3, ingest and derive. They depend only on the data (and its order), not on the
# settings, so the app runs them once per order.
derive_concepts <- function(adlb, spec = read_input("spec"), derivations = read_input("derivations"),
                            detected = detect_store(adlb, read_input("mapping"), spec)) {
  concepts <- quietly(ingest_to_concepts(
    adlb, detected$mappings, detected$domain_code,
    collect_used_concepts(spec, derivations), collect_qualified_bindings(spec, derivations)))
  quietly(apply_derivations(concepts, derivations, read_input("r_impls"),
                            read_input("unit_conversions"), detected$mappings))
}

# Run every step. Returns what each step produced, and the step that failed, if one did.
# `derived` may be passed in to skip steps 2 and 3 when only later settings changed.
engine_steps <- function(adlb, settings = DEFAULT_SETTINGS, derived = NULL) {
  engine_log <<- character(0)
  inp <- apply_settings(settings)
  spec <- inp$spec; overrides <- inp$overrides; analysis <- spec$analyses[[1]]
  derivations <- read_input("derivations")
  out <- list(settings = settings, failed = NULL, error = NULL)
  step <- function(name, expr) {
    if (!is.null(out$failed)) return(NULL)
    tryCatch(expr, error = function(e) {
      out$failed <<- name; out$error <<- conditionMessage(e); NULL
    })
  }

  out$slices <- analysis$resolvedSlices
  out$overrides <- overrides
  detected <- detect_store(adlb, read_input("mapping"), spec)
  if (is.null(derived)) {
    derived <- step("derive", derive_concepts(adlb, spec, derivations, detected))
  }
  out$derived <- derived

  cv <- step("bind", {
    cv <- quietly(build_concept_var_map(analysis$resolvedBindings, detected$mappings, overrides))
    for (role in names(analysis$analysisInputColumns)) cv$by_role[[role]] <- analysis$analysisInputColumns[[role]]
    cv
  })
  out$roles <- if (!is.null(cv)) vapply(cv$by_role, paste, character(1), collapse = " + ")

  cube <- step("slice", {
    cube <- quietly(execute_cube(derived, analysis$resolvedBindings, analysis$resolvedSlices,
                                 cv, overrides, character(0)))
    if (nrow(cube) == 0) stop("no records match the slice")
    cube
  })
  out$filters <- grep("Filter:", engine_log, value = TRUE)
  out$cube <- cube

  res <- step("fit", {
    typed <- quietly(coerce_types(cube, analysis$resolvedBindings, cv$by_concept))
    quiet_car(quietly(execute_method(typed, cv$by_role,
      parse_configs(analysis$configurationValues, read_input("method")), read_input("r_impl"))))
  })
  if (!is.null(res)) {
    out$model <- sprintf("lm(%s ~ %s + %s)", cv$by_role$response, cv$by_role$covariate, cv$by_role$fixed_effect)
    out$contrast <- res$contrasts
    b <- cube[["Measure.Result.Value__parameter_baseline"]]
    both <- !is.na(b) & !is.na(cube$BASE)
    out$n_differ <- sum(both & abs(b - cube$BASE) > 1e-9)
    out$n_both <- sum(both)
  }
  out
}

# The same records fitted three ways: as the engine ran it, with the engine's baseline in both
# places, and with ADaM's baseline in both. Shows what mixing the two baselines does.
three_fits <- function(cube, response_col = "__col_T_CFB_ANCOVA_Change_0") {
  d <- data.frame(engine_change = cube[[response_col]],
                  engine_base = cube[["Measure.Result.Value__parameter_baseline"]],
                  adam_change = cube[["Change"]], adam_base = cube[["BASE"]],
                  treatment = factor(cube[["TRT01P"]]))
  fit <- function(f) {
    m <- stats::lm(f, data = d)
    x <- as.data.frame(summary(pairs(emmeans::emmeans(m, ~ treatment), adjust = "none")))
    data.frame(estimate = x$estimate, SE = x$SE, n = stats::nobs(m))
  }
  rbind(
    cbind(model = "Mixed: engine's change, ADaM's BASE as covariate (the captured run)",
          fit(engine_change ~ adam_base + treatment)),
    cbind(model = "Engine's baseline in both", fit(engine_change ~ engine_base + treatment)),
    cbind(model = "ADaM's baseline in both (TORIVA's CHG and BASE)", fit(adam_change ~ adam_base + treatment)))
}

# The same model on TORIVA's own ADaM variables, at the chosen visit and population.
toriva_reference <- function(adlb, settings = DEFAULT_SETTINGS) {
  flag <- if (settings$population == "ITTFL") "ITTFL" else "SAFFL"
  ref <- adlb[adlb$PARAM == "Alanine Aminotransferase" & adlb$AVISIT == settings$visit &
              adlb[[flag]] %in% "Y" & adlb$ANL01FL %in% "Y", ]
  fit <- stats::lm(CHG ~ BASE + TRT01P, data = ref)
  rc <- as.data.frame(summary(pairs(emmeans::emmeans(fit, ~ TRT01P), adjust = "none")))
  list(estimate = rc$estimate, SE = rc$SE, n = stats::nobs(fit))
}

# Make the engine's arrows readable in any locale.
arrows <- function(x) gsub("<e2><86><92>|[^\\x01-\\x7f]+", "->", x, perl = TRUE, useBytes = TRUE)
