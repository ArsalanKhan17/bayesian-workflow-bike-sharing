model_formula <- function(model) {
  stopifnot(model %in% model_ids())
  f <- "cnt ~ temp_z + hum_z + windspeed_z + workingday + weather + trend_z + sin1 + cos1"
  if (model %in% c("nonlinear", "temporal")) f <- paste(f, "+ temp2 + sin2 + cos2")
  if (model == "temporal") f <- paste(f, "+ ar(time = day_index, p = 1, cov = TRUE)")
  brms::bf(as.formula(f))
}

model_family <- function(model) {
  if (model == "poisson") stats::poisson(link = "log") else brms::negbinomial(link = "log")
}

model_priors <- function(model, scale = 0.5) {
  # The brms centered intercept is the log mean at the mean design vector.
  # 3000 is an illustrative daily-demand order of magnitude, not held-out calibration.
  p <- c(brms::set_prior("normal(8.00636756765025, 1)", class = "Intercept"),
         brms::set_prior(sprintf("normal(0, %s)", scale), class = "b"))
  if (model != "poisson")
    p <- c(p, brms::set_prior("lognormal(2.30258509299405, 1)", class = "shape"))
  if (model == "temporal")
    p <- c(p, brms::set_prior("normal(0, 0.5)", class = "ar"),
           brms::set_prior("normal(0, 0.5)", class = "sderr"))
  p
}

fit_bike_model <- function(train, model, cfg, scale = 0.5, prior_only = FALSE) {
  dir.create(cfg$cache_dir, recursive = TRUE, showWarnings = FALSE)
  args <- list(formula = model_formula(model), data = train,
               family = model_family(model), prior = model_priors(model, scale),
               backend = "cmdstanr", seed = cfg$seed, chains = cfg$chains,
               iter = cfg$iter, warmup = cfg$warmup,
               cores = cfg$parallel_chains, refresh = 500,
               control = list(adapt_delta = cfg$adapt_delta, max_treedepth = cfg$max_treedepth),
               sample_prior = if (prior_only) "only" else "yes")
  if (model != "temporal") return(do.call(brms::brm, args))
  # brms 2.23 constructs a dense AR covariance matrix on every gradient.
  # The following is the identical non-centered stationary AR(1), evaluated in O(N).
  # Keep brms' formula, prior, data, parameter naming and post-processing machinery.
  skeleton <- do.call(brms::brm, c(args, list(empty = TRUE)))
  skeleton$model <- optimize_ar1_code(skeleton$model)
  stan_file <- cmdstanr::write_stan_file(skeleton$model, dir = cfg$cache_dir)
  compiled <- cmdstanr::cmdstan_model(stan_file, cpp_options = list(PRECOMPILED_HEADERS = FALSE))
  skeleton$fit <- structure(list(), CmdStanModel = compiled)
  args$formula <- NULL; args$data <- NULL; args$family <- NULL; args$prior <- NULL
  args$fit <- skeleton
  do.call(brms::brm, args)
}

optimize_ar1_code <- function(code) {
  anchors <- c("  matrix[max_nobs_tg, max_nobs_tg] Lcortime;",
               "  Lcortime = cholesky_cor_ar1(ar[1], max_nobs_tg);",
               "  err = scale_time_err(zerr, sderr, Lcortime, nobs_tg, begin_tg, end_tg);")
  if (!all(vapply(anchors, function(a) grepl(a, code, fixed = TRUE), logical(1))))
    stop("brms AR code changed: inspect the generator before using the exact recurrence optimization.")
  for (a in anchors[1:2]) code <- sub(a, "", code, fixed = TRUE)
  recurrence <- paste(
    "  // Exact stationary AR(1) Cholesky multiplication without a dense matrix.",
    "  for (g in 1:N_tg) {",
    "    err[begin_tg[g]] = sderr * zerr[begin_tg[g]] / sqrt(1 - square(ar[1]));",
    "    if (nobs_tg[g] > 1) {",
    "      for (n in (begin_tg[g] + 1):end_tg[g]) {",
    "        err[n] = ar[1] * err[n - 1] + sderr * zerr[n];",
    "      }",
    "    }",
    "  }", sep = "\n")
  sub(anchors[3], recurrence, code, fixed = TRUE)
}

fit_diagnostics <- function(fit, cfg) {
  draws <- posterior::as_draws_array(fit)
  s <- as.data.frame(posterior::summarise_draws(draws,
    "mean", "sd", ~quantile(.x, c(0.025, 0.5, 0.975)),
    "rhat", "ess_bulk", "ess_tail"))
  np <- brms::nuts_params(fit)
  energies <- split(np$Value[np$Parameter == "energy__"], np$Chain[np$Parameter == "energy__"])
  bfmi <- vapply(energies, function(e) mean(diff(e)^2) / var(e), numeric(1))
  finite_rhat <- s$rhat[is.finite(s$rhat)]
  bulk <- s$ess_bulk[is.finite(s$ess_bulk)]
  tail <- s$ess_tail[is.finite(s$ess_tail)]
  summary <- data.frame(max_rhat = max(finite_rhat), min_bulk_ess = min(bulk),
    min_tail_ess = min(tail), divergences = sum(np$Value[np$Parameter == "divergent__"]),
    treedepth_hits = sum(np$Value[np$Parameter == "treedepth__"] >= cfg$max_treedepth),
    min_bfmi = min(bfmi))
  summary$passed <- with(summary, max_rhat < 1.01 & min_bulk_ess >= 400 &
                         min_tail_ess >= 400 & divergences == 0 & treedepth_hits == 0 & min_bfmi > 0.3)
  list(parameters = s, summary = summary)
}

