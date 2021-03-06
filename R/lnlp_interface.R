#' @name simplex
#' @aliases s_map
#' 
#' @title Perform univariate forecasting

#' @details \code{\link{simplex}} is typically applied, and the embedding dimension 
#' varied, to find an optimal embedding dimension for the data. Thus, the 
#' default parameters are set so that passing a time series as the only 
#' argument will run over E = 1:10 (embedding dimension), using leave-one-out 
#' cross-validation over the whole time series, and returning just the forecast 
#' statistics.
#' 
#' \code{\link{s_map}} is typically applied, with fixed embedding dimension, and theta 
#' varied, to test for nonlinear dynamics in the data. Thus, the default 
#' parameters are set so that passing a time series as the only  argument will 
#' run over a default list of thetas (0, 0.0001, 0.0003, 0.001, 0.003, 0.01, 
#' 0.03, 0.1, 0.3, 0.5, 0.75, 1.0, 1.5, 2, 3, 4, 6, and 8), using E = 1, 
#' leave-one-out cross-validation over the whole time series, and returning 
#' just the forecast statistics.
#' 
#' norm_type "L2 norm" (default) uses the typical Euclidean distance:
#' \deqn{distance(a,b) := \sqrt{\sum_i{(a_i - b_i)^2}}
#' }{distance(a, b) := \sqrt(\sum(a_i - b_i)^2)}
#' norm_type "L1 norm" uses the Manhattan distance:
#' \deqn{distance(a,b) := \sum_i{|a_i - b_i|}
#' }{distance(a, b) := \sum|a_i - b_i|}
#' norm type "P norm" uses the LP norm, generalizing the L1 and L2 norm to use 
#'   $P$ as the exponent:
#' \deqn{distance(a,b) := \sum_i{(a_i - b_i)^P}^{1/P}
#' }{distance(a, b) := (\sum(a_i - b_i)^P)^(1/P)}
#' 
#' @param time_series either a vector to be used as the time series, or a 
#'   data.frame or matrix with at least 2 columns (in which case the first 
#'   column will be used as the time index, and the second column as the time 
#'   series)
#' @param lib a 2-column matrix (or 2-element vector) where each row specifes 
#'   the first and last *rows* of the time series to use for attractor 
#'   reconstruction
#' @param pred (same format as lib), but specifying the sections of the time 
#'   series to forecast.
#' @param norm_type the distance function to use. see 'Details'
#' @param P the exponent for the P norm
#' @param E the embedding dimensions to use for time delay embedding
#' @param tau the lag to use for time delay embedding
#' @param tp the prediction horizon (how far ahead to forecast)
#' @param num_neighbors the number of nearest neighbors to use (any of "e+1", 
#'   "E+1", "e + 1", "E + 1" will peg this parameter to E+1 for each run, any
#'   value < 1 will use all possible neighbors.)
#' @param theta the nonlinear tuning parameter (note that theta = 0 is 
#'   equivalent to an autoregressive model of order E.)
#' @param stats_only specify whether to output just the forecast statistics or 
#'   the raw predictions for each run
#' @param exclusion_radius excludes vectors from the search space of nearest 
#'   neighbors if their *time index* is within exclusion_radius (NULL turns 
#'   this option off)
#' @param epsilon excludes vectors from the search space of nearest neighbors 
#'   if their *distance* is farther away than epsilon (NULL turns this option 
#'   off)
#' @param silent prevents warning messages from being printed to the R console
#' @param save_smap_coefficients specifies whether to include the s_map 
#'   coefficients with the output (and forces the full output as if stats_only 
#'   were set to FALSE)

#' @rdname simplex
#' 
#' @description \code{\link{simplex}} uses time delay embedding on a single time 
#'   series to generate an attractor reconstruction, and then applies the 
#'   simplex projection algorithm to make forecasts.
#' 
#' @return For \code{\link{simplex}}, a data.frame with components for the parameters 
#'   and forecast statistics:
#' \describe{
#'   \item{\code{E}}{embedding dimension}
#'   \item{\code{tau}}{time lag}
#'   \item{\code{tp}}{prediction horizon}
#'   \item{\code{nn}}{number of neighbors}
#'   \item{\code{num_pred}}{number of predictions}
#'   \item{\code{rho}}{correlation coefficient between observations and predictions}
#'   \item{\code{mae}}{mean absolute error}
#'   \item{\code{rmse}}{root mean square error}
#'   \item{\code{perc}}{percent correct sign}
#'   \item{\code{p_val}}{p-value that rho is significantly greater than 0 using Fisher's 
#'   z-transformation}
#'   \item{\code{const_rho}}{same as \code{rho}, but for the constant predictor}
#'   \item{\code{const_mae}}{same as \code{mae}, but for the constant predictor}
#'   \item{\code{const_rmse}}{same as \code{rmse}, but for the constant predictor}
#'   \item{\code{const_perc}}{same as \code{perc}, but for the constant predictor}
#'   \item{\code{const_p_val}}{same as \code{p_val}, but for the constant predictor}
#' }
#'   If \code{stats_only == FALSE}, then additionally a list column:
#' \describe{
#'   \item{\code{model_output}}{data.frame with columns for the time index, 
#'     observations, predictions, and estimated prediction variance}
#' }
#' @examples 
#' data("two_species_model")
#' ts <- two_species_model$x[1:200]
#' simplex(ts, lib = c(1, 100), pred = c(101, 200))
#' 
#' data("two_species_model")
#' ts <- two_species_model$x[1:200]
#' simplex(ts, stats_only = FALSE)
#'  
simplex <- function(time_series, lib = c(1, NROW(time_series)), pred = lib, 
                    norm_type = c("L2 norm", "L1 norm", "P norm"), P = 0.5, 
                    E = 1:10, tau = 1, tp = 1, num_neighbors = "e+1", 
                    stats_only = TRUE, exclusion_radius = NULL, epsilon = NULL, 
                    silent = FALSE)
{
    # make new model object
    model <- new(LNLP)
    
    # setup data
    if (is.vector(time_series)) {
        if(!is.null(names(time_series))) {
            time <- as.numeric(names(time_series))
            if(any(is.na(time)))
                time <- seq_along(time_series)
        } else {
            time <- seq_along(time_series)
        }
    } else if ((is.matrix(time_series) || is.data.frame(time_series)) && 
               NCOL(time_series) >= 2) {
        time <- time_series[, 1]
        time_series <- time_series[, 2]
    }
    model$set_time(time)
    model$set_time_series(time_series)
           
    # setup norm and pred types
    model$set_norm_type(switch(match.arg(norm_type), 
                               "P norm" = 3, "L2 norm" = 2, "L1 norm" = 1))
    model$set_p(P)
    model$set_pred_type(2)
    
    # setup lib and pred ranges
    lib <- coerce_lib(lib, silent = silent)
    pred <- coerce_lib(pred, silent = silent)
    model$set_lib(lib)
    model$set_pred(pred)

    # handle remaining arguments and flags
    setup_model_flags(model, exclusion_radius, epsilon, silent)

    # setup other params in data.frame
    params <- expand.grid(tp, num_neighbors, tau, E)
    names(params) <- c("tp", "nn", "tau", "E")
    params <- params[, c("E", "tau", "tp", "nn")]
    e_plus_1_index <- match(num_neighbors, c("e+1", "E+1", "e + 1", "E + 1"))
    if (any(e_plus_1_index, na.rm = TRUE))
        params$nn <- params$E + 1
    params$nn <- as.numeric(params$nn)
    
    # check params
    idx <- sapply(seq(NROW(params)), function(i) {
        check_params_against_lib(params$E[i], params$tau[i], params$tp[i], lib, 
                                 silent = silent)})
    if (!any(idx))
    {
        stop("No valid parameter combinations to run, stopping.")
    }
    params <- params[idx, ]
    
    # apply model prediction function to params
    output <- lapply(seq(NROW(params)), function(i) {
        model$set_params(params$E[i], params$tau[i], params$tp[i], params$nn[i])
        model$run()
        if (stats_only)
        {
            df <- model$get_stats()
        } else {
            df <- model$get_stats()
            df$model_output <- I(list(model$get_output()))
        }
        return(df)
    })
    
    return(cbind(params, do.call(rbind, output), row.names = NULL))
}

#' @rdname simplex
#' 
#' @description \code{\link{s_map}} is similar to \code{\link{simplex}}, but uses the S-map 
#'   algorithm to make forecasts.
#' @return For \code{\link{s_map}}, the same as for \code{\link{simplex}}, but with an 
#'   additional column for the value of theta. If 
#'   \code{save_smap_coefficients == TRUE}, then an additional list-column for 
#'   the S-map coefficients.
#' @examples 
#' data("two_species_model")
#' ts <- two_species_model$x[1:200]
#' s_map(ts, E = 2)
#' 
#' data("two_species_model")
#' ts <- two_species_model$x[1:200]
#' s_map(ts, E = 2, theta = 1, save_smap_coefficients = TRUE)
#' 
s_map <- function(time_series, lib = c(1, NROW(time_series)), pred = lib, 
                  norm_type = c("L2 norm", "L1 norm", "P norm"), P = 0.5, 
                  E = 1, tau = 1, tp = 1, num_neighbors = 0, 
                  theta = c(0, 0.0001, 0.0003, 0.001, 0.003, 0.01, 0.03, 0.1, 
                            0.3, 0.5, 0.75, 1.0, 1.5, 2, 3, 4, 6, 8), 
                  stats_only = TRUE, exclusion_radius = NULL, epsilon = NULL, 
                  silent = FALSE, save_smap_coefficients = FALSE)
{
    # check inputs?
    
    # make new model object
    model <- new(LNLP)
    
    # setup data
    if (is.vector(time_series)) {
        time <- seq_along(time_series)
    } else if ((is.matrix(time_series) || is.data.frame(time_series)) && 
               NCOL(time_series) >= 2) {
        time <- time_series[, 1]
        time_series <- time_series[, 2]
    }
    model$set_time(time)
    model$set_time_series(time_series)
    
    # setup norm and pred types
    model$set_norm_type(switch(match.arg(norm_type), 
                               "P norm" = 3, "L2 norm" = 2, "L1 norm" = 1))
    model$set_p(P)
    model$set_pred_type(1)
    
    # setup lib and pred ranges
    lib <- coerce_lib(lib, silent = silent)
    pred <- coerce_lib(pred, silent = silent)
    model$set_lib(lib)
    model$set_pred(pred)
        
    # handle remaining arguments and flags
    setup_model_flags(model, exclusion_radius, epsilon, silent)
    
    # handle smap coefficients flag
    if (save_smap_coefficients)
    {
        stats_only <- FALSE
        model$save_smap_coefficients()
    }
    # setup other params in data.frame
    params <- expand.grid(theta, tp, num_neighbors, tau, E)
    names(params) <- c("theta", "tp", "nn", "tau", "E")
    params <- params[, c("E", "tau", "tp", "nn", "theta")]
    e_plus_1_index <- match(num_neighbors, c("e+1", "E+1", "e + 1", "E + 1"))
    if (any(e_plus_1_index, na.rm = TRUE))
        params$nn <- params$E + 1
    params$nn <- as.numeric(params$nn)
    
    # check params
    idx <- sapply(seq(NROW(params)), function(i) {
        check_params_against_lib(params$E[i], params$tau[i], params$tp[i], lib, 
                                 silent = silent)})
    if (!any(idx))
    {
        stop("No valid parameter combinations to run, stopping.")
    }
    params <- params[idx, ]
    
    # apply model prediction function to params
    output <- lapply(1:NROW(params), function(i) {
        model$set_params(params$E[i], params$tau[i], params$tp[i], params$nn[i])
        model$set_theta(params$theta[i])
        model$run()
        if (stats_only)
        {
            df <- model$get_stats()
        } else {
            df <- model$get_stats()
            df$model_output <- I(list(model$get_output()))
            if (save_smap_coefficients)
            {
                df$smap_coefficients <- I(list(model$get_smap_coefficients()))
            }
        }
        return(df)
    })
    
    return(cbind(params, do.call(rbind, output), row.names = NULL))
}
