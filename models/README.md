# Inspectable temporal model

`temporal-generated.stan` is the original brms 2.23.0 program for the temporal formula, priors, and final development design. `temporal-optimized.stan` replaces the dense covariance-factor evaluation with an algebraically identical stationary AR(1) recurrence. Data dimensions remain inputs to the program.

The fitted likelihood and priors are identical. The optimization removes the `Lcortime` transformed parameter, its Cholesky calculation, and the matrix multiplication used to produce `err`; it computes `err` recursively instead. Uncalled helper functions remain for a minimal, reviewable diff.

`R/models.R` generates and checks the rewrite at run time. `tests/testthat/test-prediction.R` compares dense and recursive calculations across several correlations. The original program is included for inspection, not as a second independently fitted model.

`temporal-centered.stan` is the equivalent centered-state program used only in the separately labeled computational experiment. It samples latent states directly with the stationary initial density and normal transition densities. The recorded experiment mixed poorly and is excluded from inferential results; `R/computation.R` and `scripts/compare-parameterizations.R` reproduce it. Tests verify the equality of the dense Gaussian and transition-density laws.
