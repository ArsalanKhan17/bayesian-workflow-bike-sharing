plot_theme <- function() {
  ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(panel.grid.minor = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(face = "bold", colour = "#16324f"),
      plot.title.position = "plot", legend.position = "bottom")
}

save_figure <- function(plot, name, cfg, height = 5.2) {
  path <- file.path(cfg$results_dir, "figures", paste0(name, ".png"))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(path, plot = plot + plot_theme(), width = 9, height = height, dpi = 150,
                 device = "png", type = "cairo", bg = "white")
  path
}

plot_prior_predictive <- function(prior, train, model, cfg) {
  # Work on log scale to expose, rather than hide, broad tails.
  s <- prior$summaries
  d <- data.frame(value = log10(pmax(s$mean, 1)), kind = "Prior replicate means")
  p <- ggplot2::ggplot(d, ggplot2::aes(x = value)) +
    ggplot2::geom_histogram(bins = 45, fill = "#377eb8", colour = "white") +
    ggplot2::geom_vline(xintercept = log10(mean(train$cnt)), colour = "#c44936", linewidth = 1) +
    ggplot2::labs(title = paste("What daily demand does the", model, "prior allow?"),
      subtitle = "Each replicate is a complete development-period dataset; red line is observed development mean",
      x = "log10(mean daily rentals in a replicate)", y = "Prior predictive replicates")
  save_figure(p, paste0(model, "_prior"), cfg)
}

make_model_figures <- function(fit, train, model, cfg) {
  n <- min(500L, cfg$predictive_draws)
  set.seed(cfg$seed + 21L)
  yrep <- brms::posterior_predict(fit, ndraws = n)
  mu <- brms::posterior_epred(fit, ndraws = n)
  p <- bayesplot::ppc_dens_overlay(train$cnt, yrep[seq_len(min(30, nrow(yrep))), , drop = FALSE]) +
    ggplot2::labs(title = paste("Posterior predictive distribution:", model),
      subtitle = "Observed development counts and replicated datasets; temporal check conditions on fitted states",
      x = "Daily rentals")
  paths <- save_figure(p, paste0(model, "_ppc"), cfg)
  v <- posterior::variables(posterior::as_draws_array(fit))
  trace_vars <- intersect(c("b_temp_z", "b_weatherrain_snow", "shape", "ar[1]", "sderr"), v)
  p <- bayesplot::mcmc_trace(posterior::as_draws_array(fit), pars = trace_vars) +
    ggplot2::labs(title = paste("Chain behavior:", model))
  paths <- c(paths, save_figure(p, paste0(model, "_trace"), cfg, height = 7))
  fixed <- grep("^b_", v, value = TRUE)
  s <- as.data.frame(posterior::summarise_draws(
    posterior::subset_draws(posterior::as_draws_array(fit), variable = fixed),
    "mean", ~quantile(.x, c(.025, .975))))
  names(s)[names(s) == "2.5%"] <- "lower"
  names(s)[names(s) == "97.5%"] <- "upper"
  # posterior versions use q2.5/q97.5 for named probability columns.
  if (!"lower" %in% names(s)) names(s)[3:4] <- c("lower", "upper")
  s <- s[s$variable != "b_Intercept", ]
  p <- ggplot2::ggplot(s, ggplot2::aes(y = reorder(variable, mean), x = mean)) +
    ggplot2::geom_vline(xintercept = 0, colour = "grey65", linetype = 2) +
    ggplot2::geom_segment(ggplot2::aes(x = lower, xend = upper, yend = reorder(variable, mean)),
                          colour = "#377eb8", linewidth = .9) +
    ggplot2::geom_point(colour = "#16324f", size = 2) +
    ggplot2::labs(title = paste("Coefficient uncertainty:", model),
      x = "Log-count coefficient and 95% credible interval", y = NULL)
  paths <- c(paths, save_figure(p, paste0(model, "_coefficients"), cfg, height = 6))
  mean_mu <- colMeans(mu)
  shape <- if (model == "poisson") Inf else median(posterior::as_draws_matrix(fit)[, "shape"])
  residual <- (train$cnt - mean_mu) / sqrt(mean_mu + mean_mu^2 / shape)
  lag_max <- 28L
  obs_acf <- as.numeric(stats::acf(residual, plot = FALSE, lag.max = lag_max)$acf)[-1]
  rep_acf <- t(apply(yrep, 1, function(y) {
    r <- (y - mean_mu) / sqrt(mean_mu + mean_mu^2 / shape)
    as.numeric(stats::acf(r, plot = FALSE, lag.max = lag_max)$acf)[-1]
  }))
  band <- t(apply(rep_acf, 2, quantile, c(.025, .975)))
  a <- data.frame(lag = seq_len(lag_max), observed = obs_acf, lower = band[, 1], upper = band[, 2])
  p <- ggplot2::ggplot(a, ggplot2::aes(x = lag)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = lower, ymax = upper), fill = "#c6dbef") +
    ggplot2::geom_hline(yintercept = 0, colour = "grey60") +
    ggplot2::geom_line(ggplot2::aes(y = observed), colour = "#c44936", linewidth = .8) +
    ggplot2::labs(title = paste("Dependence left in development residuals:", model),
      subtitle = "Red: observed residual ACF; blue: 95% posterior replicate envelope (pointwise)",
      y = "Residual autocorrelation", x = "Lag in days")
  paths <- c(paths, save_figure(p, paste0(model, "_acf"), cfg))
  if (model == "nonlinear") {
    reference <- train[which.min(abs(train$temp_z)), , drop = FALSE]
    curve <- reference[rep(1L, 50L), ]
    curve$temp_z <- seq(quantile(train$temp_z, .05), quantile(train$temp_z, .95), length.out = 50)
    curve$temp <- approx(train$temp_z, train$temp, xout = curve$temp_z, ties = mean)$y
    curve$temp2 <- curve$temp_z^2 - mean(train$temp_z^2 - train$temp2)
    curve$cnt <- NULL
    set.seed(cfg$seed + 33L)
    expected <- brms::posterior_epred(fit, newdata = curve, ndraws = n)
    actual <- brms::posterior_predict(fit, newdata = curve, ndraws = n)
    eq <- t(apply(expected, 2, quantile, c(.025, .5, .975)))
    pq <- t(apply(actual, 2, quantile, c(.025, .975)))
    curve$expected_lo <- eq[, 1]; curve$expected_median <- eq[, 2]; curve$expected_hi <- eq[, 3]
    curve$predictive_lo <- pq[, 1]; curve$predictive_hi <- pq[, 2]
    p <- ggplot2::ggplot(curve, ggplot2::aes(x = temp)) +
      ggplot2::geom_ribbon(ggplot2::aes(ymin = predictive_lo, ymax = predictive_hi), fill = "#dceaf5") +
      ggplot2::geom_ribbon(ggplot2::aes(ymin = expected_lo, ymax = expected_hi), fill = "#6ba5ce") +
      ggplot2::geom_line(ggplot2::aes(y = expected_median), colour = "#16324f", linewidth = .8) +
      ggplot2::labs(title = "Knowing the mean does not determine an actual day's count",
        subtitle = "Dark band: 95% expected-count interval · pale band: 95% predictive interval",
        x = "Normalized temperature; other covariates held at one observed development-day profile",
        y = "Daily rentals")
    paths <- c(paths, save_figure(p, "uncertainty_temperature", cfg),
      write_table(curve, file.path(cfg$results_dir, "temperature_scenario.csv")))
  }
  stats <- data.frame(model = model, statistic = c("mean", "sd", "max", "zero_fraction"),
    observed = c(mean(train$cnt), sd(train$cnt), max(train$cnt), mean(train$cnt == 0)),
    replicate_median = c(median(rowMeans(yrep)), median(apply(yrep, 1, sd)),
                         median(apply(yrep, 1, max)), median(rowMeans(yrep == 0))))
  c(paths, write_table(stats, file.path(cfg$results_dir, paste0(model, "_ppc_statistics.csv"))),
    write_table(a, file.path(cfg$results_dir, paste0(model, "_residual_acf.csv"))))
}

make_overview_figures <- function(raw, predictions, metrics, cfg) {
  d <- raw[raw$dteday <= as.Date("2012-09-30"), ]
  p <- ggplot2::ggplot(d, ggplot2::aes(x = dteday, y = cnt)) +
    ggplot2::geom_line(colour = "#377eb8", linewidth = .5) +
    ggplot2::labs(title = "Daily bike rentals in the development period",
      subtitle = "Capital Bikeshare, Washington, DC · final quarter held out",
      x = NULL, y = "Rentals per day")
  paths <- save_figure(p, "development_series", cfg)
  p <- ggplot2::ggplot(d, ggplot2::aes(x = temp, y = cnt, colour = factor(weathersit))) +
    ggplot2::geom_point(alpha = .65, size = 1.5) +
    ggplot2::scale_colour_manual(values = c("#377eb8", "#e8a838", "#c44936"),
      name = "Weather", labels = c("Clear", "Mist", "Rain / snow")) +
    ggplot2::labs(title = "Weather, temperature, and rental demand",
      subtitle = "Development data only; patterns mix seasonality, growth, and weather",
      x = "Normalized temperature (original UCI scale)", y = "Daily rentals")
  paths <- c(paths, save_figure(p, "weather_exploration", cfg))
  final <- predictions[predictions$split == "final" & !grepl("sensitivity", predictions$tag), ]
  final$date <- as.Date(final$date)
  p <- ggplot2::ggplot(final, ggplot2::aes(x = date)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = lo95, ymax = hi95), fill = "#dceaf5") +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = lo50, ymax = hi50), fill = "#8bb8d9") +
    ggplot2::geom_line(ggplot2::aes(y = median), colour = "#16324f", linewidth = .6) +
    ggplot2::geom_point(ggplot2::aes(y = actual), colour = "#c44936", size = .8) +
    ggplot2::facet_wrap(~model, ncol = 2, scales = "free_y") +
    ggplot2::labs(title = "Final evaluation: October–December 2012",
      subtitle = "Red: actual counts · bands: 50% and 95% predictive intervals · observed weather supplied",
      x = NULL, y = "Daily rentals")
  paths <- c(paths, save_figure(p, "final_predictions", cfg, height = 7))
  m <- metrics[!grepl("sensitivity", metrics$tag), ]
  p <- ggplot2::ggplot(m, ggplot2::aes(x = split, y = mean_log_score, colour = model, group = model)) +
    ggplot2::geom_point(ggplot2::aes(shape = sampling_passed), size = 2) + ggplot2::geom_line() +
    ggplot2::scale_shape_manual(values = c(`TRUE` = 16, `FALSE` = 4), name = "Sampling screen passed") +
    ggplot2::labs(title = "Predictive performance across chronological partitions",
      subtitle = "Higher is better; crosses mark provisional scores from failed sampling screens",
      x = "Evaluation partition", y = "Mean daily log predictive density", colour = "Model")
  c(paths, save_figure(p, "model_comparison", cfg))
}
