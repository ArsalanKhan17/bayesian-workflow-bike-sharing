#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2 || args[1] != "--profile" || !args[2] %in% c("full", "smoke"))
  stop("Usage: Rscript scripts/run.R --profile full|smoke")
Sys.setenv(BAYES_PROFILE = args[2])
options(mc.cores = min(4L, parallel::detectCores()))
if (dir.exists("cache/cmdstan/cmdstan-2.37.0"))
  cmdstanr::set_cmdstan_path(normalizePath("cache/cmdstan/cmdstan-2.37.0"))
cmdstanr::check_cmdstan_toolchain(fix = FALSE, quiet = TRUE)
targets::tar_make(store = file.path("_targets", args[2]))

