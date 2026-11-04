#!/usr/bin/env Rscript
strict <- "--strict" %in% commandArgs(trailingOnly = TRUE)
manifest <- jsonlite::read_json("results/full/manifest.json", simplifyVector = TRUE)
stopifnot(manifest$profile == "full", manifest$configuration$chains == 4,
          manifest$configuration$iter >= 4000, manifest$configuration$warmup >= 2000)
diag <- read.csv("results/full/diagnostics.csv")
stopifnot(nrow(diag) == 18L, !anyDuplicated(diag$tag))
stopifnot(all(as.integer(table(factor(diag$model,
  levels = c("poisson", "negbin", "nonlinear", "temporal")))) == c(4L,4L,6L,4L)))
recovery <- read.csv("results/full/recovery.csv")
stopifnot(nrow(recovery) == 3L, all(recovery$standardized_error < 3),
          all(recovery$rhat < 1.01), all(recovery$ess_bulk >= 400))
status <- read.csv("results/full/model_status.csv")
stopifnot(nrow(status) == 4L, sum(status$selected) == 1L,
          all(!status$selected | status$sampling_eligible))
for (model in status$model) {
  checks <- diag[diag$model == model, ]
  row <- status[status$model == model, ]
  stopifnot(row$failed_fits == sum(!checks$passed),
            row$sampling_eligible == all(checks$passed))
}
stopifnot(identical(manifest$selected_model, status$model[status$selected]))
eligible <- status[status$sampling_eligible, ]
stopifnot(status$model[status$selected] == eligible$model[which.max(eligible$cv_mean_log_score)])
if (strict) {
  stopifnot(isTRUE(manifest$analysis_ready))
  for (model in status$model[status$sampling_eligible])
    stopifnot(all(diag$passed[diag$model == model]))
  for (model in unique(diag$model[!diag$passed]))
    stopifnot(!status$sampling_eligible[status$model == model],
              nzchar(status$exclusion_reason[status$model == model]))
}
receipt <- jsonlite::read_json("results/full/checksums.json", simplifyVector = FALSE)
for (group in c("inputs", "outputs")) {
  for (path in names(receipt[[group]])) {
    if (!file.exists(path)) stop("Missing ", group, " file: ", path)
    if (!identical(digest::digest(file = path, algo = "sha256"), receipt[[group]][[path]]))
      stop("Stale ", group, " file: ", path, ". Regenerate affected results and reseal.")
  }
}
p <- read.csv("results/full/predictions.csv")
stopifnot(all(p$sampling_passed == diag$passed[match(p$tag, diag$tag)]),
          all(p$selection_eligible == status$sampling_eligible[match(p$model,status$model)]))
stopifnot(!anyNA(p), all(is.finite(p$log_score)), all(p$lo95 <= p$lo80),
          all(p$lo80 <= p$lo50), all(p$hi50 <= p$hi80), all(p$hi80 <= p$hi95))
cat("Full result contracts and source/output checksums passed.\n")

