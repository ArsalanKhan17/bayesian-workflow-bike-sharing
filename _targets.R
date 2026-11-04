library(targets)
if (dir.exists("cache/cmdstan/cmdstan-2.37.0"))
  cmdstanr::set_cmdstan_path(normalizePath("cache/cmdstan/cmdstan-2.37.0"))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
tar_option_set(packages = c("brms", "cmdstanr", "posterior", "ggplot2", "jsonlite", "digest"),
               seed = 20261104L)
list(
  tar_target(cfg, analysis_config(), cue = tar_cue(mode = "always")),
  tar_target(source_data, "data/raw/day.csv", format = "file"),
  tar_target(jobs, { source_data; analysis_jobs(cfg) }, iteration = "list"),
  tar_target(job_results, run_job(jobs, cfg), pattern = map(jobs), iteration = "list"),
  tar_target(published_results, export_results(job_results, cfg), format = "file")
)
