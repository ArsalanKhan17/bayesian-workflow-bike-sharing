# Quarto runs this from the book project directory.
path <- "../results/full/manifest.json"
if (!file.exists(path)) stop("Run Rscript scripts/run.R --profile full from the repository root first.")
m <- jsonlite::read_json(path, simplifyVector = TRUE)
if (!identical(m$profile, "full")) stop("Book requires full-profile evidence.")
if (!isTRUE(m$all_sampling_diagnostics_pass))
  message("CAUTION: sampling failures are present; the book will display them.")
dir.create("assets/generated", recursive = TRUE, showWarnings = FALSE)
figures <- list.files("../results/full/figures", pattern = "\\.png$", full.names = TRUE)
if (!length(figures) || !all(file.copy(figures, "assets/generated", overwrite = TRUE)))
  stop("Could not stage portable book figures.")

