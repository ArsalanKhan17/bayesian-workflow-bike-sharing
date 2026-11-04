#!/usr/bin/env Rscript
# One small, seeded recovery experiment checks computation and parameterization.
# It is not simulation-based calibration of the entire model family.
if (dir.exists("cache/cmdstan/cmdstan-2.37.0"))
  cmdstanr::set_cmdstan_path(normalizePath("cache/cmdstan/cmdstan-2.37.0"))
set.seed(20261104)
n <- 400L
d <- data.frame(x = rnorm(n))
truth <- c(b_Intercept = log(100), b_x = .4, shape = 8)
d$y <- rnbinom(n, mu = exp(truth[1] + truth[2] * d$x), size = truth[3])
path <- "cache/recovery.rds"
dir.create("cache", showWarnings = FALSE)
if (file.exists(path)) fit <- readRDS(path) else {
  fit <- brms::brm(y ~ x, data = d, family = brms::negbinomial(), backend = "cmdstanr",
    prior = c(brms::set_prior("normal(4.60517018598809, 1)", class = "Intercept"),
      brms::set_prior("normal(0, 0.5)", class = "b"),
      brms::set_prior("lognormal(2.30258509299405, 1)", class = "shape")),
    chains = 4, cores = 4, iter = 2000, warmup = 1000, seed = 20261104,
    control = list(adapt_delta = .99), refresh = 1000)
  saveRDS(fit, path)
}
s <- as.data.frame(posterior::summarise_draws(posterior::as_draws_array(fit),
  "mean", "sd", "rhat", "ess_bulk", ~quantile(.x, c(.025, .975))))
s <- s[match(names(truth), s$variable), ]
s$truth <- unname(truth)
s$standardized_error <- abs(s$mean - s$truth) / s$sd
stopifnot(all(s$standardized_error < 3), all(s$rhat < 1.01), all(s$ess_bulk >= 400))
dir.create("results/full", recursive = TRUE, showWarnings = FALSE)
write.csv(s, "results/full/recovery.csv", row.names = FALSE)
cat("Seeded parameter recovery passed. This is a single experiment, not full SBC.\n")

