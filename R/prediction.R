log_mean_exp <- function(x) {
  m <- max(x)
  if (!is.finite(m)) return(m)
  m + log(mean(exp(x - m)))
}

ar1_path <- function(last, phi, innovation_sd, innovations) {
  stopifnot(length(last) == nrow(innovations), length(phi) == length(last),
            length(innovation_sd) == length(last), all(abs(phi) < 1))
  ans <- matrix(NA_real_, nrow(innovations), ncol(innovations))
  state <- last
  for (j in seq_len(ncol(innovations))) {
    state <- phi * state + innovation_sd * innovations[, j]
    ans[, j] <- state
  }
  ans
}

predict_bikes <- function(fit, newdata, model, cfg) {
  # newdata$cnt is discarded BEFORE calling any prediction method.
  newdata$cnt <- NULL
  stopifnot(!anyNA(newdata), !anyDuplicated(newdata$day_index))
  if (model == "temporal") {
    stopifnot(all(diff(newdata$day_index) == 1),
              min(newdata$day_index) == max(fit$data$day_index) + 1L)
  }
  all_draws <- posterior::as_draws_matrix(fit)
  ids <- unique(as.integer(seq(1, nrow(all_draws), length.out = min(cfg$predictive_draws, nrow(all_draws)))))
  draws <- all_draws[ids, , drop = FALSE]
  # Drop latent effects from the fixed predictor, then propagate the last TRAINING state.
  eta <- brms::posterior_linpred(fit, newdata = newdata, draw_ids = ids,
                                 transform = FALSE, incl_autocor = FALSE)
  set.seed(cfg$seed + 17L)
  if (model == "temporal") {
    last_name <- paste0("err[", nrow(fit$data), "]")
    stopifnot(last_name %in% colnames(draws), "ar[1]" %in% colnames(draws),
              "sderr" %in% colnames(draws))
    innovations <- matrix(rnorm(length(eta)), nrow(eta), ncol(eta))
    eta <- eta + ar1_path(draws[, last_name], draws[, "ar[1]"], draws[, "sderr"], innovations)
  }
  mu <- exp(eta)
  if (any(!is.finite(mu))) stop("Non-finite prediction: inspect the model.")
  if (model == "poisson") {
    yrep <- matrix(rpois(length(mu), lambda = as.vector(mu)), nrow(mu))
    shape <- rep(Inf, nrow(mu))
  } else {
    shape <- draws[, "shape"]
    yrep <- matrix(rnbinom(length(mu), mu = as.vector(mu), size = rep(shape, ncol(mu))), nrow(mu))
  }
  list(mu = mu, yrep = yrep, shape = shape, draw_ids = ids)
}

score_predictions <- function(pred, actual, dates) {
  stopifnot(length(actual) == ncol(pred$mu), length(dates) == length(actual))
  q <- t(apply(pred$yrep, 2, quantile, probs = c(.025, .1, .25, .5, .75, .9, .975)))
  mean_q <- t(apply(pred$mu, 2, quantile, probs = c(.025, .5, .975)))
  lpd <- vapply(seq_along(actual), function(j) {
    ll <- if (all(is.infinite(pred$shape))) dpois(actual[j], pred$mu[, j], log = TRUE) else
      dnbinom(actual[j], mu = pred$mu[, j], size = pred$shape, log = TRUE)
    log_mean_exp(ll)
  }, numeric(1))
  data.frame(date = dates, actual = actual, mean_demand = colMeans(pred$mu),
    expected_lo95 = mean_q[, 1], expected_median = mean_q[, 2], expected_hi95 = mean_q[, 3],
    lo95 = q[, 1], lo80 = q[, 2], lo50 = q[, 3], median = q[, 4],
    hi50 = q[, 5], hi80 = q[, 6], hi95 = q[, 7], log_score = lpd,
    abs_error = abs(actual - q[, 4]),
    cover50 = actual >= q[, 3] & actual <= q[, 5], width50 = q[, 5] - q[, 3],
    cover80 = actual >= q[, 2] & actual <= q[, 6], width80 = q[, 6] - q[, 2],
    cover95 = actual >= q[, 1] & actual <= q[, 7], width95 = q[, 7] - q[, 1])
}

prior_predictive <- function(train, model, cfg, scale = 0.5, n = 1000L) {
  s <- brms::make_standata(model_formula(model), data = train,
    family = model_family(model), prior = model_priors(model, scale))
  x <- s$X[, -1, drop = FALSE]
  x <- sweep(x, 2, colMeans(x), "-")
  set.seed(cfg$seed + match(model, model_ids()))
  alpha <- rnorm(n, log(3000), 1)
  b <- matrix(rnorm(n * ncol(x), 0, scale), n, ncol(x))
  eta <- alpha + b %*% t(x)
  if (model == "temporal") {
    phi <- rnorm(n, 0, .5)
    while (any(abs(phi) >= 1)) phi[abs(phi) >= 1] <- rnorm(sum(abs(phi) >= 1), 0, .5)
    sigma <- abs(rnorm(n, 0, .5))
    initial <- rnorm(n, 0, sigma / sqrt(1 - phi^2))
    eta <- eta + ar1_path(initial, phi, sigma, matrix(rnorm(length(eta)), n))
  }
  mu <- exp(eta)
  if (model == "poisson") y <- matrix(rpois(length(mu), mu), n) else {
    shape <- rlnorm(n, log(10), 1)
    y <- matrix(rnbinom(length(mu), mu = mu, size = rep(shape, ncol(mu))), n)
  }
  stopifnot(all(is.finite(y)))
  list(draws = y, summaries = data.frame(model = model,
    replicate = seq_len(n), mean = rowMeans(y), sd = apply(y, 1, sd),
    maximum = apply(y, 1, max), zeros = rowMeans(y == 0)))
}

