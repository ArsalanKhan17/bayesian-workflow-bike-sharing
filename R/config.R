analysis_config <- function(profile = Sys.getenv("BAYES_PROFILE", "full")) {
  stopifnot(profile %in% c("full", "smoke"))
  full <- identical(profile, "full")
  list(profile = profile, seed = 20261104L,
       chains = if (full) 4L else 2L,
       iter = if (full) 4000L else 300L,
       warmup = if (full) 2000L else 150L,
       adapt_delta = if (full) 0.99 else 0.9,
       max_treedepth = 12L,
       parallel_chains = min(4L, parallel::detectCores()),
       predictive_draws = if (full) 2000L else 100L,
       results_dir = file.path("results", profile),
       cache_dir = file.path("cache", profile))
}

model_ids <- function() c("poisson", "negbin", "nonlinear", "temporal")

analysis_jobs <- function(cfg) {
  splits <- if (cfg$profile == "full") c("cv_q1", "cv_q2", "cv_q3", "final") else "final"
  jobs <- unlist(lapply(splits, function(s) lapply(model_ids(), function(m)
    list(split = s, model = m, prior_scale = 0.5, tag = paste(s, m, sep = "_")))),
    recursive = FALSE)
  if (cfg$profile == "full") {
    jobs <- c(jobs, lapply(c(0.25, 1), function(s) list(
      split = "final", model = "nonlinear", prior_scale = s,
      tag = paste0("sensitivity_", s))))
  }
  jobs
}

