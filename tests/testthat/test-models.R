testthat::test_that("likelihood comparison keeps the mean structure fixed", {
  p <- model_formula("poisson")$formula
  n <- model_formula("negbin")$formula
  testthat::expect_equal(deparse(p), deparse(n))
  testthat::expect_false(any(c("casual", "registered") %in% all.vars(p)))
  testthat::expect_match(paste(deparse(model_formula("temporal")$formula), collapse = " "), "ar\\(")
})

testthat::test_that("the recurrence rewrite fails closed when brms code changes", {
  testthat::expect_error(optimize_ar1_code("unexpected generator output"), "code changed")
  raw <- read_bikes(file.path("..", "..", "data", "raw", "day.csv"))
  p <- split_bikes(raw, "final")
  d <- apply_preprocessor(p$train, learn_preprocessor(p$train))
  code <- brms::make_stancode(model_formula("temporal"), data = d,
    family = model_family("temporal"), prior = model_priors("temporal"))
  fast <- optimize_ar1_code(code)
  testthat::expect_match(fast, "Exact stationary AR")
  testthat::expect_false(grepl("Lcortime =", fast, fixed = TRUE))
  testthat::expect_true(grepl("sderr * zerr[n]", fast, fixed = TRUE))
  centered <- center_ar1_code(code)
  testthat::expect_true(grepl("vector[N] err;  // centered", centered, fixed = TRUE))
  testthat::expect_false(grepl("vector[N] zerr;", centered, fixed = TRUE))
  testthat::expect_true(grepl("normal_lpdf(err[(begin_tg[g] + 1):end_tg[g]]", centered, fixed = TRUE))
})

