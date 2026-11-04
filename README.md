# A Bayesian workflow for bike-sharing demand

An executable case study in **R + brms + Stan**, written for intermediate practitioners. Follow one question from data provenance and priors through computation, criticism, revision, predictive evaluation, and communication.

**Question:** How are weather and calendar features associated with daily bike rentals, and how uncertain are predictions of daily demand?

The source is the [UCI Bike Sharing dataset](https://doi.org/10.24432/C5W894): 731 daily observations from Capital Bikeshare in Washington, DC, during 2011–2012. This project concerns associations and predictions conditional on supplied weather. It does not identify causal weather effects or deliver operational weather forecasts.

## Read the book

Start with [the book introduction](book/index.qmd), then follow the nine chapters in order. The rendered website is built into `book/_book/`. The Pages workflow publishes that book when this project is pushed to its GitHub repository and Pages is enabled.

| Stage | What you learn |
|---|---|
| Frame and inspect | Choose an estimand, audit provenance, prevent leakage, and reserve evaluation data |
| Specify and simulate | Write a generative count model and turn priors into simulated datasets |
| Fit and diagnose | Use NUTS, trace plots, R-hat, effective sample sizes, and sampler diagnostics |
| Criticize and revise | Compare Poisson and negative-binomial variation; introduce nonlinear mean structure |
| Model dependence | Fit a stationary latent AR(1) process and propagate future uncertainty |
| Evaluate and communicate | Use expanding-window validation, predictive scores, interval calibration, and prior sensitivity |

## Reproduce

Prerequisites: **R 4.5.x**, a working C++17/Stan toolchain, GNU Make, and **Quarto 1.8.27** or compatible. On Windows, install the Rtools version matching R. CmdStan 2.37.0 is installed locally by setup if needed. Initial installation requires Internet access; the small source CSV is included for offline analysis afterward.

For Linux x86_64, the recommended runtime is the exact Conda environment used for the executed analysis. It pins both R packages and native libraries, avoiding incompatible RStan/TBB binary combinations:

```sh
micromamba create -n bayes-workflow -f environment-linux-64.lock
micromamba activate bayes-workflow
export BAYES_SKIP_RENV=1
Rscript scripts/check-environment.R
```

GitHub Actions uses this runtime and verifies all R package versions against `renv.lock`. For a conventional R installation, leave `BAYES_SKIP_RENV` unset and use the renv setup below; native libraries must match the chosen R binaries. On Ubuntu, `igraph` also needs the GLPK runtime (`libglpk40`).

From the repository root:

```sh
Rscript scripts/setup.R
Rscript scripts/test.R
Rscript scripts/run.R --profile full
Rscript scripts/recovery.R
Rscript scripts/compare-parameterizations.R
Rscript scripts/seal-results.R
quarto render book
```

The book is a Quarto subproject, so `quarto render book` is the explicit root-level command. From `book/`, use `quarto render`. Ordinary book rendering reads generated tables and figures; it never silently launches posterior fitting. The parameterization comparison reproduces a separately labeled computational experiment; it is excluded from the retained predictive models.

For a quick execution check:

```sh
Rscript scripts/run.R --profile smoke
```

**Smoke results are not evidence.** They use two short chains and only the last 100 development days. They are written separately to `results/smoke/`; the book consumes only `results/full/`.

Full sampling starts with four chains with 2,000 warmup and 2,000 retained iterations per chain, `adapt_delta = 0.99`, and seed 20261104. Bounded diagnostic-driven refits lengthen sampling and tighten integration; every attempt is recorded. Candidates with unresolved computational failures are excluded from selection. The pipeline fits four models across three expanding-window validation periods and one final period, plus two prior-sensitivity fits. Expect substantial initial computation; actual runtimes and environment versions are recorded in the results. `targets` and local fit caches avoid repeating unchanged work.

## Statistical safeguards

- The final quarter of 2012 is reserved for confirmatory evaluation; exploration and preprocessing use development data.
- `casual` and `registered` are excluded: they sum exactly to the outcome `cnt`.
- Every chronological partition learns its own preprocessing constants.
- Temporal forecasts simulate forward from the last training state without evaluation outcomes.
- Parameter credible intervals and predictive intervals for actual daily counts are shown separately.
- All candidate diagnostics, including failures and exclusion reasons, are exported; only computationally eligible models enter selection.
- AR(1) computation uses an algebraically identical recurrence in generated brms Stan code. See the temporal chapter and numerical equivalence tests.

## Project layout

```text
book/             Quarto chapters, references, and presentation
R/                data, models, prediction, figures, pipeline
scripts/          setup, execution, testing, validation, and publishing
tests/testthat/   data, leakage, scoring, and AR-process tests
data/raw/         original daily CSV, original readme, and checksums
results/full/     compact numerical results, figures, and run manifest
results/smoke/    execution checks, clearly separated from full results
cache/            ignored fitted models and CmdStan installation
_targets/         ignored dependency-aware pipeline stores
renv.lock         pinned R package dependencies
```

## Evaluation design

| Partition | Training ends | Evaluation period |
|---|---|---|
| CV Q1 | 2011-12-31 | Jan–Mar 2012 |
| CV Q2 | 2012-03-31 | Apr–Jun 2012 |
| CV Q3 | 2012-06-30 | Jul–Sep 2012 |
| Final | 2012-09-30 | Oct–Dec 2012 |

Scores are **daily marginal predictive log densities**, MAE of predictive medians, and predictive interval coverage/width. These are fixed-origin, multi-day predictions conditional on supplied weather, with no updating from evaluation rental counts. They are not joint trajectory scores or rolling one-step-ahead forecasts. Ordinary pointwise LOO is not used as a substitute for this temporal evaluation.

## Publish

After committing the project and authenticating the GitHub CLI, run:

```sh
bash scripts/publish.sh
```

The script validates the evidence, creates `ArsalanKhan17/bayesian-workflow-bike-sharing` if needed, pushes `main`, and requests GitHub Pages enablement. It stops on an unexpected `origin` remote. If starting from a source ZIP, initialize and commit it as a Git repository first. GitHub Actions must be selected as the Pages publishing source.

## Licensing and citation

Project code and original teaching text: MIT. The source dataset remains under **CC BY 4.0**, as stated on UCI; the original readme and citations are preserved. See [data documentation](data/README.md), [LICENSE](LICENSE), and [CITATION.cff](CITATION.cff).

