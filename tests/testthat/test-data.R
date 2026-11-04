testthat::test_that("source data satisfy the audited grain and checksum", {
  # test_dir changes working directory to the tests directory.
  x <- read_bikes(file.path("..", "..", "data", "raw", "day.csv"))
  testthat::expect_equal(nrow(x), 731L)
  testthat::expect_true(all(x$cnt == x$casual + x$registered))
  p <- tempfile(fileext = ".csv")
  writeLines("tampered source", p)
  testthat::expect_error(read_bikes(p), "checksum")
  unlink(p)
})

testthat::test_that("partitions are chronological and reserve the final quarter", {
  x <- read_bikes(file.path("..", "..", "data", "raw", "day.csv"))
  expected <- c(cv_q1 = 91L, cv_q2 = 91L, cv_q3 = 92L, final = 92L)
  for (s in names(expected)) {
    p <- split_bikes(x, s)
    testthat::expect_equal(nrow(p$test), unname(expected[s]))
    testthat::expect_true(max(p$train$dteday) < min(p$test$dteday))
    testthat::expect_length(intersect(p$train$dteday, p$test$dteday), 0)
    if (s != "final") testthat::expect_true(max(p$test$dteday) <= as.Date("2012-09-30"))
  }
})

testthat::test_that("preprocessing cannot use future observations or leaked columns", {
  x <- read_bikes(file.path("..", "..", "data", "raw", "day.csv"))
  p <- split_bikes(x, "final")
  prep <- learn_preprocessor(p$train)
  p$test$temp <- 1000; p$test$cnt <- 999999L
  testthat::expect_identical(prep, learn_preprocessor(p$train))
  train <- apply_preprocessor(p$train, prep)
  testthat::expect_equal(mean(train$temp_z), 0, tolerance = 1e-12)
  testthat::expect_equal(sd(train$temp_z), 1, tolerance = 1e-12)
  testthat::expect_equal(mean(train$temp2), 0, tolerance = 1e-12)
  testthat::expect_false(any(c("casual", "registered", "instant", "atemp") %in% names(train)))
  testthat::expect_equal(levels(train$weather), c("clear", "mist", "rain_snow"))
})

