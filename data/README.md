# Data provenance and dictionary

Source: [UCI Bike Sharing](https://archive.ics.uci.edu/dataset/275/bike+sharing+dataset), dataset 275, DOI [10.24432/C5W894](https://doi.org/10.24432/C5W894).

The original archive is downloaded from `https://archive.ics.uci.edu/static/public/275/bike+sharing+dataset.zip`. `raw/day.csv` and `raw/Readme.txt` are preserved byte-for-byte. Download time and SHA-256 checksums are in `raw/provenance.json`. The analysis verifies the CSV checksum before reading it.

**License:** UCI displays [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) for this dataset. Original authorship remains with the dataset creator. The source readme also requests citation of the introductory paper:

Fanaee-T, H. and Gama, J. (2014). Event labeling combining ensemble detectors and background knowledge. *Progress in Artificial Intelligence*, 2, 113–127. Online publication 2013. DOI [10.1007/s13748-013-0040-3](https://doi.org/10.1007/s13748-013-0040-3).

## Grain and verified size

One row is one day of aggregate Capital Bikeshare rentals in Washington, DC. There are **731 consecutive dates**, 2011-01-01 through 2012-12-31, with no missing cells or duplicate dates. The archive's hourly file has 17,379 records; some UCI landing-page summary counts differ, so this project uses counts verified directly from the daily source file.

| Source field | Meaning | Modeling treatment |
|---|---|---|
| `instant` | Record index | Excluded; derive elapsed time from the date |
| `dteday` | Calendar date | Ordering, split boundaries, Fourier seasonality, trend |
| `season` | Encoded season | Excluded; source readme and UCI page labels differ |
| `yr`, `mnth` | Year indicator and month | Excluded; replaced by continuous trend and annual harmonics |
| `holiday`, `weekday` | Holiday and day-of-week encodings | Excluded in the chosen compact mean model |
| `workingday` | Neither weekend nor holiday | Binary predictor |
| `weathersit` | Weather category | Factor: 1 clear; 2 mist/cloud; 3 light rain/snow |
| `temp` | Normalized temperature | Standardized using training mean/SD; retain original normalized scale |
| `atemp` | Normalized apparent temperature | Excluded to avoid overlapping temperature predictors |
| `hum` | Relative humidity divided by 100 | Standardized using training mean/SD |
| `windspeed` | Normalized windspeed | Standardized using training mean/SD |
| `casual`, `registered` | Components of rental counts | **Excluded: direct outcome leakage** |
| `cnt` | Total daily rentals | Nonnegative integer response |

The daily file contains weather categories 1, 2, and 3, with frequencies 463, 247, and 21 across the full source. Category 4 appears only in the hourly file and is not a daily factor level. Sparse adverse-weather days limit effect estimation.

Temperature normalization descriptions differ between archive and landing-page documentation, particularly daily versus hourly scales. We do not manufacture a Celsius conversion. Effects are reported per training SD or on the original normalized scale.

The observations cover one system over only two years. Fleet size, pricing, population, service availability, and disruptive events are not fully represented. Rental counts are realized usage, not unconstrained demand or distinct customers.

