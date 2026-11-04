# Generated evidence

`full/` contains numerical summaries, predictive scores, figures, provenance, and software versions from the full analysis. A manifest distinguishes completed computations from successful sampling screens. The book reads only this directory.

Each `*_draws.csv.gz` preserves final-development-fit draws for regression coefficients and dispersion/dependence parameters, with chain and iteration identifiers. Read one using `read.csv(gzfile("results/full/nonlinear_draws.csv.gz"), check.names = FALSE)`. Per-day latent states and large fitted-model objects remain in the local cache.

`smoke/` is ignored by Git. It is created by the short execution profile and must not be used for scientific conclusions.

Each `*_sampling_attempts.csv`, when present, preserves an initial failed computational screen and the subsequent longer run. Final `diagnostics.csv` contains the retained fit's diagnostics, with its actual iteration and warmup counts.

`checksums.json` seals the analysis source and published results. After a deliberate change, rerun affected computations before executing `Rscript scripts/seal-results.R`. Resealing stale outputs is not a substitute for regenerating them.

`model_status.csv` records computational eligibility, exclusions, and the model selected by development-period scores. `sampling_passed` flags each scored fit; `selection_eligible` flags the candidate as a whole. Failed-candidate scores remain provisional and do not enter selection. The manifest's `analysis_ready` requires a computationally accepted selected analysis; `all_sampling_diagnostics_pass` separately reports whether every candidate fit passed, including rejected candidates.

Metric definitions:

- `mean_log_score`: mean daily marginal log predictive density; larger is better.
- `mae`: mean absolute error of the posterior predictive median, in daily rentals.
- `coverage50/80/95`: realized proportions inside central posterior predictive intervals.
- `width50/80/95`: average corresponding interval widths, in daily rentals.
- `expected_lo95/expected_hi95` in prediction tables: intervals for expected counts, including simulated latent-state uncertainty in the temporal model; these exclude count observation noise.
- `lo95/hi95`: predictive intervals for realized counts, including count noise.

Final-quarter scoring is conditional on supplied recorded weather and calendar features. Temporal predictions propagate from the final training state without evaluation outcomes. Per-day marginal scores are not full joint trajectory scores.
