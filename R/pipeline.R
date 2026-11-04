write_table <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write.csv(x, path, row.names = FALSE, na = "")
  path
}

run_job <- function(job, cfg) {
  raw <- read_bikes()
  partition <- split_bikes(raw, job$split)
  prep <- learn_preprocessor(partition$train)
  train <- apply_preprocessor(partition$train, prep)
  test <- apply_preprocessor(partition$test, prep)
  if (cfg$profile == "smoke") train <- tail(train, 100)
  dir.create(cfg$cache_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(cfg$results_dir, recursive = TRUE, showWarnings = FALSE)
  prior_paths <- character()
  if (job$split == "final" && !grepl("sensitivity", job$tag)) {
    # Simulate the specified model before fitting its posterior.
    priors <- prior_predictive(train, job$model, cfg)
    prior_paths <- c(write_table(priors$summaries,
      file.path(cfg$results_dir, paste0(job$model, "_prior_predictive.csv"))),
      plot_prior_predictive(priors, train, job$model, cfg))
  }
  fingerprint <- digest::digest(list(job, cfg, train,
    lapply(file.path("R", c("config.R", "data.R", "models.R")),
           function(p) readLines(p, warn = FALSE))))
  cache_path <- file.path(cfg$cache_dir, paste0(job$tag, "_", fingerprint, ".rds"))
  start <- proc.time()[["elapsed"]]
  if (file.exists(cache_path)) fit <- readRDS(cache_path) else {
    fit <- fit_bike_model(train, job$model, cfg, job$prior_scale)
    attr(fit, "fit_wall_seconds") <- proc.time()[["elapsed"]] - start
    saveRDS(fit, cache_path, compress = FALSE)
  }
  elapsed <- proc.time()[["elapsed"]] - start
  if (!is.null(attr(fit, "fit_wall_seconds"))) elapsed <- attr(fit, "fit_wall_seconds")
  effective_cfg <- cfg
  saved_control <- attr(fit, "sampling_control")
  if (!is.null(saved_control)) for (n in names(saved_control)) effective_cfg[[n]] <- saved_control[[n]]
  diagnostics <- fit_diagnostics(fit, effective_cfg)
  # Adapt computation only to training-fit sampler diagnostics, never predictive scores.
  # Preserve both attempts, rather than concealing an initially inadequate run.
  if (cfg$profile == "full" && !diagnostics$summary$passed &&
      is.null(attr(fit, "sampling_attempts"))) {
    message("Sampling screen failed for ", job$tag, "; doubling warmup and retained iterations.")
    initial <- diagnostics$summary
    initial$iter <- cfg$iter; initial$warmup <- cfg$warmup; initial$attempt <- 1L
    initial$adapt_delta <- cfg$adapt_delta; initial$max_treedepth <- cfg$max_treedepth
    retry_cfg <- cfg
    retry_cfg$iter <- 2L * cfg$iter; retry_cfg$warmup <- 2L * cfg$warmup
    if (initial$divergences > 0) retry_cfg$adapt_delta <- 0.999
    if (initial$divergences > 0 || initial$treedepth_hits > 0) retry_cfg$max_treedepth <- 14L
    retry_start <- proc.time()[["elapsed"]]
    fit <- fit_bike_model(train, job$model, retry_cfg, job$prior_scale)
    elapsed <- elapsed + proc.time()[["elapsed"]] - retry_start
    diagnostics <- fit_diagnostics(fit, retry_cfg)
    final_attempt <- diagnostics$summary
    final_attempt$iter <- retry_cfg$iter; final_attempt$warmup <- retry_cfg$warmup
    final_attempt$attempt <- 2L
    final_attempt$adapt_delta <- retry_cfg$adapt_delta
    final_attempt$max_treedepth <- retry_cfg$max_treedepth
    attr(fit, "sampling_attempts") <- rbind(initial, final_attempt)
    attr(fit, "sampling_iterations") <- c(iter = retry_cfg$iter, warmup = retry_cfg$warmup)
    attr(fit, "sampling_control") <- list(adapt_delta = retry_cfg$adapt_delta,
                                          max_treedepth = retry_cfg$max_treedepth)
    effective_cfg <- retry_cfg
    attr(fit, "fit_wall_seconds") <- elapsed
    saveRDS(fit, cache_path, compress = FALSE)
  }
  if (cfg$profile == "full" && job$model == "temporal" &&
      !diagnostics$summary$passed && !is.null(attr(fit, "sampling_attempts")) &&
      effective_cfg$adapt_delta < 0.999) {
    message("Persistent temporal sampling failure for ", job$tag,
            "; refitting with adapt_delta=0.9999 and treedepth cap 16.")
    attempts <- attr(fit, "sampling_attempts")
    retry_cfg <- cfg
    retry_cfg$iter <- 2L * cfg$iter; retry_cfg$warmup <- 2L * cfg$warmup
    retry_cfg$adapt_delta <- 0.9999; retry_cfg$max_treedepth <- 16L
    retry_start <- proc.time()[["elapsed"]]
    fit <- fit_bike_model(train, job$model, retry_cfg, job$prior_scale)
    elapsed <- elapsed + proc.time()[["elapsed"]] - retry_start
    diagnostics <- fit_diagnostics(fit, retry_cfg)
    final_attempt <- diagnostics$summary
    final_attempt$iter <- retry_cfg$iter; final_attempt$warmup <- retry_cfg$warmup
    final_attempt$attempt <- max(attempts$attempt) + 1L
    final_attempt$adapt_delta <- retry_cfg$adapt_delta
    final_attempt$max_treedepth <- retry_cfg$max_treedepth
    attr(fit, "sampling_attempts") <- rbind(attempts, final_attempt)
    attr(fit, "sampling_iterations") <- c(iter = retry_cfg$iter, warmup = retry_cfg$warmup)
    attr(fit, "sampling_control") <- list(adapt_delta = retry_cfg$adapt_delta,
                                          max_treedepth = retry_cfg$max_treedepth)
    attr(fit, "fit_wall_seconds") <- elapsed
    effective_cfg <- retry_cfg
    saveRDS(fit, cache_path, compress = FALSE)
  }
  iterations <- attr(fit, "sampling_iterations")
  if (is.null(iterations)) iterations <- c(iter = cfg$iter, warmup = cfg$warmup)
  diagnostics$summary$iter <- iterations[["iter"]]
  diagnostics$summary$warmup <- iterations[["warmup"]]
  diagnostics$summary$adapt_delta <- effective_cfg$adapt_delta
  diagnostics$summary$max_treedepth <- effective_cfg$max_treedepth
  diagnostics$summary$model <- job$model; diagnostics$summary$split <- job$split
  diagnostics$summary$tag <- job$tag; diagnostics$summary$seconds <- elapsed
  diagnostics$summary$n_train <- nrow(train); diagnostics$summary$n_test <- nrow(test)
  pars <- diagnostics$parameters
  pars <- pars[!grepl("^(err\\[|zerr\\[|prior_|lprior|lp__)", pars$variable), ]
  predictions <- score_predictions(predict_bikes(fit, test, job$model, cfg), test$cnt, test$dteday)
  predictions$model <- job$model; predictions$split <- job$split; predictions$tag <- job$tag
  paths <- c(prior_paths,
    write_table(diagnostics$summary, file.path(cfg$results_dir, paste0(job$tag, "_diagnostics.csv"))),
    write_table(pars, file.path(cfg$results_dir, paste0(job$tag, "_parameters.csv"))),
    write_table(predictions, file.path(cfg$results_dir, paste0(job$tag, "_predictions.csv"))))
  attempts <- attr(fit, "sampling_attempts")
  if (!is.null(attempts))
    paths <- c(paths, write_table(attempts,
      file.path(cfg$results_dir, paste0(job$tag, "_sampling_attempts.csv"))))
  jsonlite::write_json(prep, file.path(cfg$results_dir, paste0(job$tag, "_preprocessing.json")),
                        auto_unbox = TRUE, pretty = TRUE)
  if (job$split == "final" && !grepl("sensitivity", job$tag)) {
    paths <- c(paths, make_model_figures(fit, train, job$model, cfg))
    keep <- grep("^(b_|shape$|ar\\[|sderr$)",
                 posterior::variables(posterior::as_draws_array(fit)), value = TRUE)
    compact <- as.data.frame(posterior::as_draws_df(posterior::subset_draws(
      posterior::as_draws_array(fit), variable = keep)))
    draw_path <- file.path(cfg$results_dir, paste0(job$model, "_draws.csv.gz"))
    connection <- gzfile(draw_path, "wt")
    write.csv(compact, connection, row.names = FALSE)
    close(connection)
    paths <- c(paths, draw_path)
    # Scenario contrasts hold the latent process at zero for the temporal model.
    # These are conditional association summaries, not causal interventions.
    scenario <- train[which.min(abs(train$temp_z)), , drop = FALSE]
    scenario <- scenario[rep(1L, 2L), ]
    scenario$weather <- factor(c("clear", "rain_snow"), levels = levels(train$weather))
    mu <- brms::posterior_epred(fit, newdata = scenario, incl_autocor = FALSE,
                                ndraws = cfg$predictive_draws)
    ratio <- mu[, 2] / mu[, 1]
    contrast <- data.frame(model = job$model, contrast = "rain_snow / clear at same covariates",
      median_ratio = median(ratio), lo95 = quantile(ratio, .025), hi95 = quantile(ratio, .975),
      probability_below_one = mean(ratio < 1))
    paths <- c(paths, write_table(contrast, file.path(cfg$results_dir, paste0(job$model, "_contrast.csv"))))
  }
  list(job = job, paths = paths, cache = cache_path, fingerprint = fingerprint,
       diagnostic_passed = diagnostics$summary$passed)
}

export_results <- function(results, cfg) {
  paths <- unlist(lapply(results, `[[`, "paths"))
  prediction_paths <- paths[grepl("_predictions.csv$", paths)]
  pred <- do.call(rbind, lapply(prediction_paths, read.csv))
  split_groups <- split(pred, pred$tag)
  metrics <- do.call(rbind, lapply(split_groups, function(d) data.frame(
    model = d$model[1], split = d$split[1], tag = d$tag[1], n = nrow(d),
    mean_log_score = mean(d$log_score), mae = mean(d$abs_error),
    coverage50 = mean(d$cover50), width50 = mean(d$width50),
    coverage80 = mean(d$cover80), width80 = mean(d$width80),
    coverage95 = mean(d$cover95), width95 = mean(d$width95))))
  diagnostic_paths <- paths[grepl("_diagnostics.csv$", paths)]
  diag <- do.call(rbind, lapply(diagnostic_paths, read.csv))
  if (cfg$profile == "full") {
    status <- do.call(rbind, lapply(model_ids(), function(model) {
      checks <- diag[diag$model == model, ]
      cv <- metrics[metrics$model == model & grepl("^cv_", metrics$split), ]
      data.frame(model = model, required_fits = nrow(checks),
        failed_fits = sum(!checks$passed), sampling_eligible = all(checks$passed),
        cv_mean_log_score = sum(cv$mean_log_score * cv$n) / sum(cv$n),
        exclusion_reason = if (all(checks$passed)) "" else
          paste("Sampling screens failed:", paste(checks$tag[!checks$passed], collapse = ", ")))
    }))
    eligible <- status[status$sampling_eligible, ]
    selected <- if (nrow(eligible)) eligible$model[which.max(eligible$cv_mean_log_score)] else NA_character_
    status$selected <- status$model %in% selected
  } else {
    status <- data.frame(model = model_ids(), sampling_eligible = FALSE, selected = FALSE)
    selected <- NA_character_
  }
  metrics$sampling_passed <- diag$passed[match(metrics$tag, diag$tag)]
  metrics$selection_eligible <- status$sampling_eligible[match(metrics$model, status$model)]
  pred$sampling_passed <- diag$passed[match(pred$tag, diag$tag)]
  pred$selection_eligible <- status$sampling_eligible[match(pred$model, status$model)]
  paths <- c(paths,
    write_table(metrics, file.path(cfg$results_dir, "metrics.csv")),
    write_table(diag, file.path(cfg$results_dir, "diagnostics.csv")),
    write_table(pred, file.path(cfg$results_dir, "predictions.csv")),
    write_table(status, file.path(cfg$results_dir, "model_status.csv")),
    make_overview_figures(raw = read_bikes(), predictions = pred, metrics = metrics, cfg = cfg))
  manifest <- list(profile = cfg$profile, created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    configuration = cfg, versions = list(R = R.version.string,
      brms = as.character(utils::packageVersion("brms")),
      cmdstan = as.character(cmdstanr::cmdstan_version()),
      quarto = tryCatch(system2("quarto", "--version", stdout = TRUE), error = function(e) "not on PATH")),
    all_sampling_diagnostics_pass = all(diag$passed),
    analysis_ready = cfg$profile == "full" && !is.na(selected) &&
      all(diag$passed[diag$model == selected]),
    selected_model = selected,
    interpretation = "Conditional on supplied weather; multi-day AR paths never condition on evaluation outcomes.",
    sources = list(day_csv_sha256 = digest::digest(file = "data/raw/day.csv", algo = "sha256")),
    jobs = lapply(results, function(r) list(tag = r$job$tag, fingerprint = r$fingerprint)))
  jsonlite::write_json(manifest, file.path(cfg$results_dir, "manifest.json"),
                        pretty = TRUE, auto_unbox = TRUE, digits = 16)
  writeLines(capture.output(sessionInfo()), file.path(cfg$results_dir, "session-info.txt"))
  paths <- c(paths, file.path(cfg$results_dir, c("manifest.json", "session-info.txt")))
  # Analysis readiness is explicit; never silently claim sampling diagnostics passed.
  if (cfg$profile == "full" && !all(diag$passed))
    warning("Some full-run sampling diagnostics failed. Inspect diagnostics.csv before interpretation.")
  unique(paths)
}
