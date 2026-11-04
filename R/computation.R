center_ar1_code <- function(code) {
  replacements <- c(
    "  vector[N] zerr;  // unscaled residuals" = "  vector[N] err;  // centered latent residuals",
    "  vector[N] err;  // actual residuals" = "",
    "  matrix[max_nobs_tg, max_nobs_tg] Lcortime;" = "",
    "  Lcortime = cholesky_cor_ar1(ar[1], max_nobs_tg);" = "",
    "  err = scale_time_err(zerr, sderr, Lcortime, nobs_tg, begin_tg, end_tg);" = "")
  for (old in names(replacements)) {
    if (!grepl(old, code, fixed = TRUE)) stop("brms AR generator changed; inspect centered rewrite.")
    code <- sub(old, replacements[[old]], code, fixed = TRUE)
  }
  old <- "  target += std_normal_lpdf(zerr);"
  if (!grepl(old, code, fixed = TRUE)) stop("Missing latent-state prior anchor.")
  density <- paste(
    "  // Same stationary AR(1) law, with states sampled in centered coordinates.",
    "  for (g in 1:N_tg) {",
    "    target += normal_lpdf(err[begin_tg[g]] | 0, sderr / sqrt(1 - square(ar[1])));",
    "    if (nobs_tg[g] > 1) {",
    "      target += normal_lpdf(err[(begin_tg[g] + 1):end_tg[g]] |",
    "                            ar[1] * err[begin_tg[g]:(end_tg[g] - 1)], sderr);",
    "    }",
    "  }", sep = "\n")
  sub(old, density, code, fixed = TRUE)
}

fit_centered_temporal <- function(train, cfg, scale = 0.5) {
  skeleton <- brms::brm(formula = model_formula("temporal"), data = train,
    family = model_family("temporal"), prior = model_priors("temporal", scale),
    backend = "cmdstanr", sample_prior = "yes", empty = TRUE)
  skeleton$model <- center_ar1_code(skeleton$model)
  path <- cmdstanr::write_stan_file(skeleton$model, dir = cfg$cache_dir)
  compiled <- cmdstanr::cmdstan_model(path, cpp_options = list(PRECOMPILED_HEADERS = FALSE))
  skeleton$fit <- structure(list(), CmdStanModel = compiled)
  brms::brm(fit = skeleton, chains = cfg$chains, cores = cfg$parallel_chains,
    iter = cfg$iter, warmup = cfg$warmup, seed = cfg$seed, refresh = 1000,
    control = list(adapt_delta = cfg$adapt_delta, max_treedepth = cfg$max_treedepth))
}
