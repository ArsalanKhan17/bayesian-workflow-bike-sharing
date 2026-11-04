#!/usr/bin/env Rscript
# Conda supplies native libraries; renv.lock remains the R-version contract.
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite is required to check the environment.")
lock <- jsonlite::read_json("renv.lock", simplifyVector = FALSE)
required <- vapply(lock$Packages, function(x) x$Version, character(1))
installed <- utils::installed.packages()
actual <- installed[match(names(required), installed[, "Package"]), "Version"]
missing <- names(required)[is.na(actual)]
wrong <- names(required)[!is.na(actual) & actual != required]
if (length(missing)) stop("Missing locked R packages: ", paste(missing, collapse = ", "))
if (length(wrong)) stop("R package versions differ from renv.lock: ", paste(wrong, collapse = ", "))
if (as.character(getRversion()) != lock$R$Version)
  stop("Expected R ", lock$R$Version, "; found ", as.character(getRversion()))
cat("Verified R", lock$R$Version, "and", length(required), "locked R package versions.\n")

