#!/usr/bin/env Rscript
options(repos = c(CRAN = "https://cloud.r-project.org"))
if (Sys.getenv("BAYES_SKIP_RENV") == "1") {
  source("scripts/check-environment.R")
} else {
  if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
  if (file.exists("renv.lock")) renv::restore(prompt = FALSE) else
    stop("Run this script from the repository root with renv.lock present.")
}
if (!requireNamespace("cmdstanr", quietly = TRUE))
  stop("cmdstanr was not restored. Check the Stan R repository in renv.lock.")
cmdstanr::check_cmdstan_toolchain(fix = FALSE, quiet = FALSE)
if (inherits(try(cmdstanr::cmdstan_path(), silent = TRUE), "try-error")) {
  dir.create("cache/cmdstan", recursive = TRUE, showWarnings = FALSE)
  cmdstanr::install_cmdstan(dir = normalizePath("cache/cmdstan"),
                           version = "2.37.0", cores = 2, quiet = FALSE)
}
cat("Setup complete. Run Rscript scripts/run.R --profile full\n")

