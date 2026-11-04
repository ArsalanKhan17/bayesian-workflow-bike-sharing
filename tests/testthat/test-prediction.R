testthat::test_that("AR recurrence is the stationary covariance parameterization", {
  set.seed(72)
  for (rho in c(-.9, -.2, 0, .5, .95)) {
    n <- 12L; sigma <- .3; z <- rnorm(n)
    covariance <- sigma^2 / (1 - rho^2) * rho^abs(outer(seq_len(n), seq_len(n), "-"))
    dense <- as.vector(t(chol(covariance)) %*% z)
    recurrence <- numeric(n)
    recurrence[1] <- sigma * z[1] / sqrt(1 - rho^2)
    for (i in 2:n) recurrence[i] <- rho * recurrence[i - 1] + sigma * z[i]
    testthat::expect_equal(recurrence, dense, tolerance = 1e-10)
  }
})

testthat::test_that("future AR states propagate innovations and uncertainty correctly", {
  out <- ar1_path(last = c(2, -1), phi = c(.5, -.5), innovation_sd = c(1, 2),
                 innovations = matrix(c(1, 0, 0, 1), 2, 2))
  testthat::expect_equal(out, matrix(c(2, .5, 1, 1.75), 2, 2))
  testthat::expect_error(ar1_path(0, 1, 1, matrix(0, 1, 2)))
  set.seed(93)
  n <- 30000L
  states <- ar1_path(rep(0, n), rep(.8, n), rep(.3, n), matrix(rnorm(n * 5), n))
  expected_variance <- .3^2 * (1 - .8^(2 * seq_len(5))) / (1 - .8^2)
  testthat::expect_equal(apply(states, 2, var), expected_variance, tolerance = .006)
})

testthat::test_that("centered AR transition density equals its dense Gaussian law", {
  set.seed(811)
  for (rho in c(-.9, 0, .7, .98)) {
    n <- 10L; sigma <- .25; x <- rnorm(n, 0, .2)
    covariance <- sigma^2 / (1 - rho^2) * rho^abs(outer(seq_len(n), seq_len(n), "-"))
    lower <- t(chol(covariance))
    dense <- -.5 * (n * log(2*pi) + 2*sum(log(diag(lower))) + sum(solve(lower,x)^2))
    transitions <- dnorm(x[1], 0, sigma/sqrt(1-rho^2), log=TRUE) +
      sum(dnorm(x[-1], rho*x[-n], sigma, log=TRUE))
    testthat::expect_equal(transitions, dense, tolerance=1e-10)
  }
})

testthat::test_that("log predictive scores average probabilities, not log probabilities", {
  p <- list(mu = matrix(c(1, 5), 2, 1), shape = c(Inf, Inf),
            yrep = matrix(c(0, 1, 2, 3, 4, 5), 6, 1))
  s <- score_predictions(p, actual = 2, dates = as.Date("2012-10-01"))
  testthat::expect_equal(s$log_score, log(mean(dpois(2, c(1, 5)))))
  testthat::expect_true(s$lo95 <= s$lo80 && s$lo80 <= s$lo50)
  testthat::expect_true(s$hi50 <= s$hi80 && s$hi80 <= s$hi95)
  testthat::expect_equal(s$width95, s$hi95 - s$lo95)
})

testthat::test_that("temporal predictions are invariant to evaluation outcomes", {
  fit_paths <- list.files(file.path("..", "..", "cache", "full"),
    pattern = "^final_temporal_.*\\.rds$", full.names = TRUE)
  testthat::skip_if(length(fit_paths) == 0, "Full temporal fit not cached; run full profile for integration check.")
  fit <- readRDS(tail(fit_paths, 1))
  raw <- read_bikes(file.path("..", "..", "data", "raw", "day.csv"))
  parts <- split_bikes(raw, "final")
  prep <- learn_preprocessor(parts$train)
  d <- apply_preprocessor(parts$test, prep)
  cfg <- analysis_config("full"); cfg$predictive_draws <- 100L
  first <- predict_bikes(fit, d, "temporal", cfg)
  d$cnt <- rev(d$cnt) + 999999L
  second <- predict_bikes(fit, d, "temporal", cfg)
  testthat::expect_identical(first, second)
  testthat::expect_error(predict_bikes(fit, d[nrow(d):1, ], "temporal", cfg))
})

