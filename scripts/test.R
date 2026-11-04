#!/usr/bin/env Rscript
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
testthat::test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)

