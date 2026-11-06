# What the app learns about each dataset when it is uploaded at step 8:
# its columns, and the distinct values of each character column with 50 or fewer.
# Mirrors loadXptFile() in ac-dc-app/js/utils/webr-engine.js.
# Usage: Rscript capture/dataset-meta.R <adlb.parquet> <adsl.parquet> <out.json>
args <- commandArgs(TRUE)
meta <- list()
for (path in args[1:2]) {
  d <- as.data.frame(nanoparquet::read_parquet(path))
  name <- tolower(sub("\\.parquet$", "", basename(path)))
  dv <- lapply(d, function(col) {
    if (!is.character(col)) return(NULL)
    v <- sort(unique(col[!is.na(col)]))
    if (length(v) > 0 && length(v) <= 50) v else NULL
  })
  meta[[name]] <- list(name = name, nrow = nrow(d), ncol = ncol(d),
                       columns = colnames(d), distinctValues = Filter(Negate(is.null), dv))
}
writeLines(jsonlite::toJSON(meta, auto_unbox = TRUE), args[3])
