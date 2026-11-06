# Setup: the pins, the packages, the data and the engine.
# Sourced by walkthrough.R; nothing here makes an analysis decision.

PINS <- list(
  engine = list(
    repo   = "cdisc-org/analysis-concepts",
    commit = "739344ca31203bb502efeee2b855286e17977be6",
    file   = "ac-dc-app/r/acdc_engine.R",
    md5    = "0cb7d2898e605e3aa1c445c4d47b0323"
  ),
  data = list(
    repo   = "OpenTrialReporting/torivumab-nsclc-301",
    commit = "a8066307b976351b53a9ffa447a69047306e4cb9",
    file   = "datasets/adam/adlb.parquet",
    md5    = "4add95a534d8d2b9267048c01b698091"
  )
)

need <- c("jsonlite", "nanoparquet", "car", "emmeans")
missing <- need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  stop("Install these packages first:\n  install.packages(c(",
       paste0('"', missing, '"', collapse = ", "), "))", call. = FALSE)
}

# TORIVA's ADLB at the pinned commit, downloaded once and checked.
adlb_path <- file.path("data", "adlb.parquet")
if (!file.exists(adlb_path)) {
  dir.create("data", showWarnings = FALSE)
  url <- sprintf("https://raw.githubusercontent.com/%s/%s/%s",
                 PINS$data$repo, PINS$data$commit, PINS$data$file)
  message("Downloading TORIVA's ADLB (1.8 MB) from ", url)
  utils::download.file(url, adlb_path, mode = "wb", quiet = TRUE)
}
if (unname(tools::md5sum(adlb_path)) != PINS$data$md5) {
  stop(adlb_path, " is not the pinned file. Delete it and run again.", call. = FALSE)
}

# The engine: CDISC's file, unmodified (see vendor/analysis-concepts/SOURCE.md).
engine_path <- file.path("vendor", "analysis-concepts", "acdc_engine.R")
# In the published app (R in the browser, through webR) Shinylive stores text files in its own
# way, so the bytes differ; the publishing workflow runs this same check before it builds the
# site, and the engine's non-ASCII characters are only in comments and printed messages.
in_browser <- grepl("emscripten", R.version$platform, fixed = TRUE)
if (!in_browser && unname(tools::md5sum(engine_path)) != PINS$engine$md5) {
  stop(engine_path, " differs from the pinned engine.", call. = FALSE)
}
source(file.path("vendor", "analysis-concepts", "acdc_engine.R"))

# The nine inputs the app hands the engine (see inputs/README.md).
read_input <- function(name) {
  jsonlite::fromJSON(file.path("inputs", paste0(name, ".json")), simplifyVector = FALSE)
}

# The engine reports as it goes; keep that for anyone who wants it,
# and show only what each step is about.
engine_log <- character(0)
quietly <- function(expr) {
  out <- utils::capture.output(value <- expr)
  engine_log <<- c(engine_log, out)
  value
}

# car::Anova() warns that the treatment names contain "+" ("Torivumab + Chemotherapy").
# The warning is about how it prints a hypothesis, not about the result; silence that one only.
quiet_car <- function(expr) {
  withCallingHandlers(expr, warning = function(w) {
    if (grepl("arithmetic operators", conditionMessage(w))) invokeRestart("muffleWarning")
  })
}
