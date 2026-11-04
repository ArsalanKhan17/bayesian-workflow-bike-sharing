root <- normalizePath("..")
results <- file.path(root, "results", "full")
table_result <- function(name, digits = 3, ...) {
  x <- read.csv(file.path(results, name), check.names = FALSE)
  knitr::kable(x, digits = digits, ...)
}
read_result <- function(name) read.csv(file.path(results, name), check.names = FALSE)
figure_result <- function(name) knitr::include_graphics(file.path("assets", "generated", paste0(name, ".png")))
show_source <- function(name) {
  text <- readLines(file.path(root, name), warn = FALSE)
  cat("```r\n", paste(text, collapse = "\n"), "\n```\n", sep = "")
}
manifest <- jsonlite::read_json(file.path(results, "manifest.json"), simplifyVector = TRUE)
if (!identical(manifest$profile, "full")) stop("The teaching book requires full-profile results.")

