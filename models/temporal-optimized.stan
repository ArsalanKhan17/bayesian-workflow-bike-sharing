// generated with brms 2.23.0
functions {
  /* integer sequence of values
   * Args:
   *   start: starting integer
   *   end: ending integer
   * Returns:
   *   an integer sequence from start to end
   */
  array[] int sequence(int start, int end) {
    array[end - start + 1] int seq;
    for (n in 1:num_elements(seq)) {
      seq[n] = n + start - 1;
    }
    return seq;
  }
  // are two 1D integer arrays equal?
  int is_equal(array[] int a, array[] int b) {
    int n_a = size(a);
    int n_b = size(b);
    if (n_a != n_b) {
      return 0;
    }
    for (i in 1:n_a) {
      if (a[i] != b[i]) {
        return 0;
      }
    }
    return 1;
  }

  /* grouped data stored linearly in "data" as indexed by begin and end
   * is repacked to be stacked into an array of vectors.
   */
  array[] vector stack_vectors(vector long_data, int n, array[] int stack,
                               array[] int begin, array[] int end) {
    int S = sum(stack);
    int G = size(stack);
    array[S] vector[n] stacked;
    int j = 1;
    for (i in 1:G) {
      if (stack[i] == 1) {
        stacked[j] = long_data[begin[i]:end[i]];
        j += 1;
      }
    }
    return stacked;
  }
  /* compute the cholesky factor of an AR1 correlation matrix
   * Args:
   *   ar: AR1 autocorrelation
   *   nrows: number of rows of the covariance matrix
   * Returns:
   *   A nrows x nrows matrix
   */
   matrix cholesky_cor_ar1(real ar, int nrows) {
     matrix[nrows, nrows] mat;
     vector[nrows - 1] gamma;
     mat = diag_matrix(rep_vector(1, nrows));
     for (i in 2:nrows) {
       gamma[i - 1] = pow(ar, i - 1);
       for (j in 1:(i - 1)) {
         mat[i, j] = gamma[i - j];
         mat[j, i] = gamma[i - j];
       }
     }
     return cholesky_decompose(mat ./ (1 - ar^2));
   }
  /* scale and correlate time-series residuals
   * using the Cholesky factor of the correlation matrix
   * Args:
   *   zerr: standardized and independent residuals
   *   sderr: standard deviation of the residuals
   *   chol_cor: cholesky factor of the correlation matrix
   *   nobs: number of observations in each group
   *   begin: the first observation in each group
   *   end: the last observation in each group
   * Returns:
   *   vector of scaled and correlated residuals
   */
   vector scale_time_err(vector zerr, real sderr, matrix chol_cor,
                         array[] int nobs, array[] int begin, array[] int end) {
     vector[rows(zerr)] err;
     for (i in 1:size(nobs)) {
       matrix[nobs[i], nobs[i]] L_i;
       L_i = sderr * chol_cor[1:nobs[i], 1:nobs[i]];
       err[begin[i]:end[i]] = L_i * zerr[begin[i]:end[i]];
     }
     return err;
   }
}
data {
  int<lower=1> N;  // total number of observations
  array[N] int Y;  // response variable
  int<lower=1> K;  // number of population-level effects
  matrix[N, K] X;  // population-level design matrix
  int<lower=1> Kc;  // number of population-level effects after centering
  // data needed for ARMA correlations
  int<lower=0> Kar;  // AR order
  int<lower=0> Kma;  // MA order
  // see the functions block for details
  int<lower=1> N_tg;
  array[N_tg] int<lower=1> begin_tg;
  array[N_tg] int<lower=1> end_tg;
  array[N_tg] int<lower=1> nobs_tg;
  int prior_only;  // should the likelihood be ignored?
}
transformed data {
  matrix[N, Kc] Xc;  // centered version of X without an intercept
  vector[Kc] means_X;  // column means of X before centering
  int max_lag = max(Kar, Kma);
  int max_nobs_tg = max(nobs_tg);  // maximum dimension of the autocorrelation matrix
  for (i in 2:K) {
    means_X[i - 1] = mean(X[, i]);
    Xc[, i - 1] = X[, i] - means_X[i - 1];
  }
}
parameters {
  vector[Kc] b;  // regression coefficients
  real Intercept;  // temporary intercept for centered predictors
  vector[N] zerr;  // unscaled residuals
  real<lower=0> sderr;  // SD of residuals
  vector<lower=-1,upper=1>[Kar] ar;  // autoregressive coefficients
  real<lower=0> shape;  // shape parameter
}
transformed parameters {
  vector[N] err;  // actual residuals
  // cholesky factor of the autocorrelation matrix

  // prior contributions to the log posterior
  real lprior = 0;
  // compute residual covariance matrix

  // compute correlated time-series residuals
  // Exact stationary AR(1) Cholesky multiplication without a dense matrix.
  for (g in 1:N_tg) {
    err[begin_tg[g]] = sderr * zerr[begin_tg[g]] / sqrt(1 - square(ar[1]));
    if (nobs_tg[g] > 1) {
      for (n in (begin_tg[g] + 1):end_tg[g]) {
        err[n] = ar[1] * err[n - 1] + sderr * zerr[n];
      }
    }
  }
  lprior += normal_lpdf(b | 0, 0.5);
  lprior += normal_lpdf(Intercept | 8.00636756765025, 1);
  lprior += normal_lpdf(sderr | 0, 0.5)
    - 1 * normal_lccdf(0 | 0, 0.5);
  lprior += normal_lpdf(ar | 0, 0.5)
    - 1 * log_diff_exp(normal_lcdf(1 | 0, 0.5), normal_lcdf(-1 | 0, 0.5));
  lprior += lognormal_lpdf(shape | 2.30258509299405, 1);
}
model {
  // likelihood including constants
  if (!prior_only) {
    // initialize linear predictor term
    vector[N] mu = rep_vector(0.0, N);
    mu += Intercept + Xc * b + err;
    target += neg_binomial_2_log_lpmf(Y | mu, shape);
  }
  // priors including constants
  target += lprior;
  target += std_normal_lpdf(zerr);
}
generated quantities {
  // actual population-level intercept
  real b_Intercept = Intercept - dot_product(means_X, b);
  // additionally sample draws from priors
  real prior_b = normal_rng(0,0.5);
  real prior_Intercept = normal_rng(8.00636756765025,1);
  real prior_sderr = normal_rng(0,0.5);
  real prior_ar = normal_rng(0,0.5);
  real prior_shape = lognormal_rng(2.30258509299405,1);
  // use rejection sampling for truncated priors
  while (prior_sderr < 0) {
    prior_sderr = normal_rng(0,0.5);
  }
  while (prior_ar < -1 || prior_ar > 1) {
    prior_ar = normal_rng(0,0.5);
  }
  while (prior_shape < 0) {
    prior_shape = lognormal_rng(2.30258509299405,1);
  }
}

