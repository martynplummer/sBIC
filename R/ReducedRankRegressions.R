setConstructorS3("ReducedRankRegressions",
                 function(numResponses = 1, numCovariates = 1, maxRank = 0) {
                   numModels = maxRank + 1
                   prior = rep(1, numModels)

                   # Generate the partial order of the models
                   if (numModels == 1) {
                     E = matrix(numeric(0), ncol = 2)
                     g = igraph::graph.empty(1)
                   } else {
                     E = cbind(seq(1, numModels - 1), seq(2, numModels))
                     g = igraph::graph.edgelist(E, directed = TRUE)
                   }
                   topOrder = as.numeric(igraph::topological.sort(g))

                   dimension = rep(NA, numModels)

                   extend(
                     ModelPoset(),
                     "ReducedRankRegressions",
                     .numModels = numModels,
                     .prior = prior,
                     .E = E,
                     .posetAsGraph = g,
                     .topOrder = topOrder,
                     .dimension = dimension,
                     .numResponses = numResponses,
                     .numCovariates = numCovariates,
                     .maxRank = maxRank
                   )
                 })

setMethodS3("getTopOrder", "ReducedRankRegressions", function(this) {
  return(this$.topOrder)
}, appendVarArgs = F)

setMethodS3("getPrior", "ReducedRankRegressions", function(this) {
  return(this$.prior)
}, appendVarArgs = F)

setMethodS3("getNumModels", "ReducedRankRegressions", function(this) {
  return(this$.numModels)
}, appendVarArgs = F)

setMethodS3("setData", "ReducedRankRegressions", function(this, XY) {
  X = XY$X
  Y = XY$Y
  if (nrow(X) != this$.numCovariates || nrow(Y) != this$.numResponses ||
      ncol(X) != ncol(Y)) {
    throw("Input data XY has incorrect dimensions.")
  }
  this$.X = X
  this$.Y = Y
  this$.logLikes = rep(NA, this$getNumModels())
  this$.unconstrainedMLE = NA
}, appendVarArgs = F)

setMethodS3("getData", "ReducedRankRegressions", function(this) {
  if (is.null(this$.X)) {
    throw("Data has not yet been set")
  }
  return(list(X = this$.X, Y = this$.Y))
}, appendVarArgs = F)

setMethodS3("getNumSamples", "ReducedRankRegressions", function(this) {
  return(ncol(this$getData()$X))
}, appendVarArgs = F)

setMethodS3("parents", "ReducedRankRegressions", function(this, model) {
  if (model > this$getNumModels() ||
      model < 1 || length(model) != 1) {
    throw("Invalid input model.")
  }
  if (model == 1) {
    return(numeric(0))
  } else {
    return(model - 1)
  }
}, appendVarArgs = F)

setMethodS3("logLikeMleHelper", "ReducedRankRegressions", function(this, model) {
  if (!is.matrix(this$.unconstrainedMLE)) {
    X = this$.X
    Y = this$.Y
    this$.unconstrainedMLE = Y %*% t(X) %*% solve(X %*% t(X))
    if (!is.matrix(this$.unconstrainedMLE)) {
      throw("Unexpected error in logLikeMleHelper.")
    }
    this$.Yhat = this$.unconstrainedMLE %*% X
    this$.S <- svd(this$.Yhat)
  }
}, appendVarArgs = F)

setMethodS3("logLikeMle", "ReducedRankRegressions", function(this, model) {
  if (!is.na(this$.logLikes[model])) {
    return(this$.logLikes[model])
  }
  X = this$.X
  Y = this$.Y
  H = model - 1 # Rank
  this$logLikeMleHelper() # Sets up the variables .C, .Yhat, and .S if they
                          # haven't been computed yet.
  C = this$.C # unconstrained MLE
  Yhat = this$.Yhat # Y predictions under the unconstrainted model
  S = this$.S # SVD of YHat

  if (H == 0) {
    UH <- matrix(0, nrow(S$u), 1)
  } else{
    UH <- S$u[, 1:H]
  }

  M = this$.numCovariates
  N = this$.numResponses

  if (H < min(M, N)) {
      ell = -1 / 2 * sum((Y - Yhat) ^ 2) - 1 / 2 * sum(S$d[(H + 1):length(S$d)] ^ 2)
  } else {
    ## no singular values
    ell = -1 / 2 * sum((Y - Yhat) ^ 2)
  }
  this$.logLikes[model] = ell
  return(this$.logLikes[model])
}, appendVarArgs = F)

setMethodS3("learnCoef", "ReducedRankRegressions", function(this, superModel, subModel) {
  ## MxH, NxH matrix sizes
  M = this$.numCovariates
  N = this$.numResponses
  H = superModel
  r = subModel
  if (r > H) {
    return(this$learnCoef(H, H))
  }

  ## case 1
  if ((N + r <= M + H) && (M + r <= N + H) && (H + r <= M + N)) {
    if (((M + H + N + r) %% 2) == 0) {
      m = 1
      lambda = -(H + r) ^ 2 - M ^ 2 - N ^ 2 + 2 * (H + r) * (M + N) + 2 *
        M * N
      lambda = lambda / 8
    }
    else{
      m = 2
      lambda = -(H + r) ^ 2 - M ^ 2 - N ^ 2 + 2 * (H + r) * (M + N) + 2 *
        M * N + 1
      lambda = lambda / 8
    }

  }
  else{
    ## case 2
    if (M + H < N + r) {
      m = 1
      lambda = H * M - H * r + N * r
      lambda = lambda / 2
    }
    else{
      ## case 3
      if (N + H < M + r) {
        m = 1
        lambda = H * N - H * r + M * r
        lambda = lambda / 2
      }
      else{
        ## case 4
        if (M + N < H + r) {
          m = 1
          lambda = M * N / 2
        }
      }
    }
  }
  return(list(lambda = lambda, m = m))
}, appendVarArgs = F)

setMethodS3("getDimension", "ReducedRankRegressions", function(this, model) {
  if (!anyNA(this$.dimension[model])) {
   return(this$.dimension[model])
  }
  for (i in model) {
    if (is.na(this$.dimension[i])) {
      this$.dimension[i] = 2 * this$learnCoef(i, i)$lambda
    }
  }
  return(this$.dimension[model])
}, appendVarArgs = F)