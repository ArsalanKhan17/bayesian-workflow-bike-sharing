read_bikes <- function(path = "data/raw/day.csv") {
  expected <- "a6bcf826782d3c0fbfdcbeead17cd0884185a0dafe8ff10cd48a874ee7ba18be"
  if (!identical(digest::digest(file = path, algo = "sha256"), expected))
    stop("Source data checksum mismatch. Do not silently replace the dataset.")
  x <- read.csv(path, stringsAsFactors = FALSE)
  required <- c("instant", "dteday", "season", "yr", "mnth", "holiday", "weekday",
                "workingday", "weathersit", "temp", "atemp", "hum", "windspeed",
                "casual", "registered", "cnt")
  stopifnot(identical(names(x), required), nrow(x) == 731L, !anyNA(x))
  x$dteday <- as.Date(x$dteday)
  stopifnot(!anyDuplicated(x$dteday), all(diff(x$dteday) == 1),
            min(x$dteday) == as.Date("2011-01-01"),
            max(x$dteday) == as.Date("2012-12-31"),
            all(x$cnt >= 0 & x$cnt == floor(x$cnt)),
            all(x$casual + x$registered == x$cnt),
            all(x$weathersit %in% 1:3), all(x$workingday %in% 0:1),
            all(x$temp >= 0 & x$temp <= 1), all(x$hum >= 0 & x$hum <= 1),
            all(x$windspeed >= 0 & x$windspeed <= 1))
  x
}

split_bikes <- function(x, split) {
  boundaries <- list(
    cv_q1 = c("2011-12-31", "2012-03-31"),
    cv_q2 = c("2012-03-31", "2012-06-30"),
    cv_q3 = c("2012-06-30", "2012-09-30"),
    final = c("2012-09-30", "2012-12-31"))
  stopifnot(split %in% names(boundaries))
  b <- as.Date(boundaries[[split]])
  train <- x[x$dteday <= b[1], ]
  test <- x[x$dteday > b[1] & x$dteday <= b[2], ]
  stopifnot(max(train$dteday) < min(test$dteday), !any(train$dteday %in% test$dteday))
  list(train = train, test = test)
}

calendar_features <- function(x) {
  # Only an explicit allow-list enters the modeling frame: never user-count components.
  d <- data.frame(dteday = x$dteday, cnt = x$cnt,
                  day_index = as.integer(x$dteday - as.Date("2011-01-01")) + 1L,
                  temp = x$temp, hum = x$hum, windspeed = x$windspeed,
                  workingday = x$workingday,
                  weather = factor(x$weathersit, levels = 1:3,
                                   labels = c("clear", "mist", "rain_snow")))
  years <- as.integer(format(d$dteday, "%Y"))
  days <- ifelse(years %% 4 == 0 & (years %% 100 != 0 | years %% 400 == 0), 366, 365)
  phase <- 2 * pi * (as.integer(format(d$dteday, "%j")) - 1) / days
  d$sin1 <- sin(phase); d$cos1 <- cos(phase)
  d$sin2 <- sin(2 * phase); d$cos2 <- cos(2 * phase)
  d$trend <- (d$day_index - 1) / 365.25
  d
}

learn_preprocessor <- function(train) {
  d <- calendar_features(train)
  cols <- c("temp", "hum", "windspeed", "trend")
  centers <- vapply(d[cols], mean, numeric(1))
  scales <- vapply(d[cols], sd, numeric(1))
  stopifnot(all(is.finite(scales)), all(scales > 0))
  temp_z <- (d$temp - centers[["temp"]]) / scales[["temp"]]
  list(centers = centers, scales = scales, temp2_center = mean(temp_z^2),
       training_end = max(train$dteday))
}

apply_preprocessor <- function(x, prep) {
  d <- calendar_features(x)
  for (col in names(prep$centers))
    d[[paste0(col, "_z")]] <- (d[[col]] - prep$centers[[col]]) / prep$scales[[col]]
  d$temp2 <- d$temp_z^2 - prep$temp2_center
  d
}

