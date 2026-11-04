#!/usr/bin/env Rscript
# Optional computational experiment: the probability model and priors stay fixed.
if (dir.exists("cache/cmdstan/cmdstan-2.37.0"))
  cmdstanr::set_cmdstan_path(normalizePath("cache/cmdstan/cmdstan-2.37.0"))
for (f in list.files("R", full.names = TRUE)) source(f)
cfg <- analysis_config("full")
x <- split_bikes(read_bikes(), "cv_q1")$train
train <- apply_preprocessor(x, learn_preprocessor(x))
path <- "cache/centered-pilot.rds"
if (file.exists(path)) fit <- readRDS(path) else {
  fit <- fit_centered_temporal(train, cfg)
  saveRDS(fit, path)
}
diagnostic <- fit_diagnostics(fit, cfg)$summary
diagnostic$split <- "cv_q1"
diagnostic$parameterization <- "centered"
diagnostic$used_for_inference <- FALSE
write_table(diagnostic, "results/full/centered_experiment.csv")
cat("Experiment recorded; it is not part of the retained predictive analysis.\n")
