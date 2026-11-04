#!/usr/bin/env Rscript
source_files <- function() {
  code <- unlist(lapply(c("R", "scripts", "book", "data", "models", ".github"), function(d)
    list.files(d, recursive = TRUE, full.names = TRUE, all.files = TRUE)))
  code <- code[!grepl("(^|/)(_book|\\.quarto)(/|$)", code)]
  code <- code[!grepl("^book/assets/generated/", code)]
  sort(unique(c(code, "_targets.R", "renv.lock", "environment-linux-64.lock", "DESCRIPTION", ".Rprofile",
                ".gitattributes", ".gitignore", ".renvignore",
                "renv/activate.R", "renv/settings.json")))
}
if (!file.exists("results/full/manifest.json")) stop("Run full analysis before sealing.")
inputs <- source_files()
outputs <- list.files("results/full", recursive = TRUE, full.names = TRUE)
outputs <- outputs[!grepl("checksums.json$", outputs)]
hashes <- function(paths) setNames(lapply(paths, function(p) digest::digest(file = p, algo = "sha256")), paths)
receipt <- list(created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
                inputs = hashes(inputs), outputs = hashes(outputs))
jsonlite::write_json(receipt, "results/full/checksums.json", auto_unbox = TRUE, pretty = TRUE)
cat("Sealed", length(inputs), "input files and", length(outputs), "result files.\n")

