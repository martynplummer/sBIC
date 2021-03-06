#' @include ModelPoset.R
NULL
#' Construct a poset of gaussian latent forest models.
#'
#' For a fixed binary forest where all leaves represent observed variables this
#' function creates an object representing all gaussian latent forest models
#' that are submodels of the given model. All models are enumerated from 1 to
#' the total number of subforests, see the method \code{\link{getSupport.LatentForests}}
#' for details on how to determine which model a particular model number
#' corresponds to. Models are naturally ordered by inclusion so that, for
#' example, the forest that has no edges is less than all other models.
#'
#' @name LatentForests
#' @export
#'
#' @param numLeaves the number of observed variables (these are the leaves of
#'                  the model)
#' @param E a 2xm matrix of edges corresponding to the edges of the 'super
#'          forest' f for which we compute all subforests. f should have nodes
#'          1:numLeaves as leaves of the forest with no internal nodes as leaves.
#'
#' @return An object representing the collection.
setConstructorS3("LatentForests",
                 function(numLeaves = 0,
                          E = matrix(numeric(0), ncol = 2)) {
                   if (!isBinaryEdgelistVecOrMat(E, numLeaves)) {
                     throw(paste("E is not a valid binary edge list matrix for",
                                 "the given number of leaves ."))
                   }
                   E = edgesInRootedDAGOrder(E)
                   subModels = getSubModelSupports(numLeaves, E)
                   numModels = nrow(subModels)
                   prior = rep(1, numModels)

                   # Generate the partial order of the models
                   posetAsGraph = subModelsToDAG(subModels)
                   topOrder <- igraph::topological.sort(posetAsGraph)
                   tree <- igraph::graph.edgelist(E, directed = F)

                   # Parameters
                   dimension = rep(0, numModels)
                   for (j in topOrder) {
                     aE = getSubmodelEdges(subModels[j, ], E)
                     dimension[j] = forestDim(aE, rep(1, nrow(aE)), numLeaves)
                   }

                   extend(
                     ModelPoset(),
                     "LatentForests",
                     .E = E,
                     .subModels = subModels,
                     .numModels = numModels,
                     .prior = prior,
                     .topOrder = topOrder,
                     .tree = tree,
                     .dimension = dimension,
                     .posetAsGraph = posetAsGraph,
                     .numLeaves = numLeaves
                   )
                 })

#' @rdname   getTopOrder
#' @name     getTopOrder.LatentForests
#' @export
setMethodS3("getTopOrder", "LatentForests", function(this) {
  return(this$.topOrder)
}, appendVarArgs = F)

#' @rdname   getPrior
#' @name     getPrior.LatentForests
#' @export
setMethodS3("getPrior", "LatentForests", function(this) {
  return(this$.prior)
}, appendVarArgs = F)

#' @rdname   getNumModels
#' @name     getNumModels.LatentForests
#' @export
setMethodS3("getNumModels", "LatentForests", function(this) {
  return(this$.numModels)
}, appendVarArgs = F)

#' Set data for the latent forest models.
#'
#' Sets the data to be used by the latent forest models models for computing
#' MLEs.
#'
#' @name     setData.LatentForests
#' @export
#'
#' @param this the LatentForests object.
#' @param data the data to be set, should matrix of observed values where each row
#'        corresponds to a single sample.
#'
setMethodS3("setData", "LatentForests", function(this, data) {
  this$.X = data
  this$.sampleCovMat = t(data) %*% data
  this$.logLikes = rep(NA, this$getNumModels())
  this$.mles = rep(list(NA), this$getNumModels())
}, appendVarArgs = F)

#' @rdname   getData
#' @name     getData.LatentForests
#' @export
setMethodS3("getData", "LatentForests", function(this) {
  if (is.null(this$.X)) {
    throw("No data has been set for models.")
  }
  return(this$.X)
}, appendVarArgs = F)

#' @rdname   getNumSamples
#' @name     getNumSamples.LatentForests
#' @export
setMethodS3("getNumSamples", "LatentForests", function(this) {
  return(nrow(this$getData()))
}, appendVarArgs = F)

#' @rdname   parents
#' @name     parents.LatentForests
#' @export
setMethodS3("parents", "LatentForests", function(this, model) {
  if (length(model) != 1) {
    throw("parents can only accept a single model.")
  }
  return(as.numeric(igraph::neighbors(this$.posetAsGraph, model, "in")))
}, appendVarArgs = F)

#' @rdname   logLikeMle
#' @name     logLikeMle.LatentForests
#' @export
setMethodS3("logLikeMle", "LatentForests", function(this, model, ...) {
  if (!is.na(this$.logLikes[model])) {
    return(this$.logLikes[model])
  }
  emResults = this$emMain(model, starts = 5, maxIter = 1000, tol = 1e-4)
  this$.mles[[model]] = emResults$covMat
  this$.logLikes[model] = emResults$logLike
  return(this$.logLikes[model])
}, appendVarArgs = F)

#' @rdname   mle
#' @name     mle.LatentForests
#' @export
setMethodS3("mle", "LatentForests", function(this, model) {
  if (!is.na(this$.mle[[model]])) {
    return(this$.mle[[model]])
  }
  this$logLikeMle(model)
  return(this$.mle[[model]])
}, appendVarArgs = F)

#' @rdname   learnCoef
#' @name     learnCoef.LatentForests
#' @export
setMethodS3("learnCoef", "LatentForests", function(this, superModel, subModel) {
  support = this$getSupport(superModel)
  subSupport = this$getSupport(subModel)
  E = this$getAllEdges()
  numLeaves = this$getNumLeaves()

  w.sum = 0
  m = 1
  if (!all(support == subSupport)) {
    # Compute w sum (primary lambda component)
    subEdges = E[subSupport == 1, , drop = F]
    qForestNodes = union(subEdges, 1:numLeaves)

    for (it in 1:length(support)) {
      if (support[it] - subSupport[it] == 1) {
        w.sum = w.sum + sum(E[it, ] %in% qForestNodes)
      }
    }

    # Compute multiplicity
    nodeDegsBig = table(E[support == 1, , drop = F])
    deg2NodesBig = as.numeric(names(nodeDegsBig[nodeDegsBig == 2]))
    m = 1 + length(setdiff(deg2NodesBig, qForestNodes))
  }

  lambda = this$getDimension(subModel) / 2 + w.sum / 4

  return(list(lambda = lambda, m = m))
}, appendVarArgs = F)

#' @rdname   getDimension
#' @name     getDimension.LatentForests
#' @export
setMethodS3("getDimension", "LatentForests", function(this, model) {
  return(this$.dimension[model])
}, appendVarArgs = F)

#' Sampling covariance matrix.
#'
#' Returns the sampling covariance matrix for the data set with setData().
#'
#' @name     getSamplingCovMat
#' @export
#'
#' @param this the LatentForests object.
getSamplingCovMat <- function(this) {
    UseMethod("getSamplingCovMat")
}
#' @rdname   getSamplingCovMat
#' @name     getSamplingCovMat.LatentForests
#' @export
setMethodS3("getSamplingCovMat", "LatentForests", function(this) {
  if (is.null(this$.X)) {
    throw("No data has been set for models.")
  }
  return(this$.sampleCovMat)
}, appendVarArgs = F, private = T)

#' Get support for a given model.
#'
#' Given a model number returns the support of the model. Let E by the matrix
#' of edges returned by this$getAllEdges(), the support is represented by a
#' 0-1 vector v where the ith entry of v is 1 if the ith edge in E is in the
#' model and is 0 otherwise.
#'
#' @name     getSupport
#' @export
#'
#' @param this the LatentForests object.
#' @param model the model number.
getSupport <- function(this, model) {
    UseMethod("getSupport")
}
#' @rdname   getSupport
#' @name     getSupport.LatentForests
#' @export
setMethodS3("getSupport", "LatentForests", function(this, model) {
  return(this$.subModels[model, ])
}, appendVarArgs = F)

#' Edges representing the largest model.
#'
#' When creating the LatentForests object a set of edges representing the
#' largest model is required. This function returns those edges as a matrix.
#' This matrix will have edges in the same order but may have flipped which
#' node comes first in any particular edge. That is if edge (1,4) was the
#' 5th edge then it will remain the 5th edge but may now be of the form (4,1).
#'
#' @name     getAllEdges
#' @export
#'
#' @param this the LatentForests object.
#' @param model the model number.
getAllEdges <- function(this, model) {
    UseMethod("getAllEdges")
}
#' @rdname   getAllEdges
#' @name     getAllEdges.LatentForests
#' @export
setMethodS3("getAllEdges", "LatentForests", function(this, model) {
  return(this$.E)
}, appendVarArgs = F)

#' Get number of leaves.
#'
#' Gets the number of leaves in the latent forest models.
#'
#' @name     getNumLeaves
#' @export
#'
#' @param this the LatentForests object.
getNumLeaves <- function(this) {
    UseMethod("getNumLeaves")
}
#' @rdname   getNumLeaves
#' @name     getNumLeaves.LatentForests
#' @export
setMethodS3("getNumLeaves", "LatentForests", function(this) {
  return(this$.numLeaves)
}, appendVarArgs = F)

#' Maximum number of vertices.
#'
#' A private method for LatentForests that computes the number
#' of vertices a tree with this$getNumLeaves() number of leaves has.
#'
#' @name     getNumVertices
#' @export
#'
#' @param this the LatentForests object.
getNumVertices <- function(this) {
    UseMethod("getNumVertices")
}
#' @rdname   getNumVertices
#' @name     getNumVertices.LatentForests
#' @export
setMethodS3("getNumVertices", "LatentForests", function(this) {
  numLeaves = this$getNumLeaves()
  if (numLeaves == 0) {
    return(0)
  }
  return(max(2 * this$getNumLeaves() - 2, 1))
}, appendVarArgs = F, private = T)

#' Get model with the given support.
#'
#' Returns the model number corresponding to a given 0-1 vector representing
#' the support of the model. This support should corresponds to the edges
#' returned by this$getAllEdges()
#'
#' @name     getModelWithSupport
#' @export
#'
#' @param this the LatentForests object.
#' @param support the 0-1 vector representing the support.
getModelWithSupport <- function(this, support) {
    UseMethod("getModelWithSupport")
}
#' @rdname   getModelWithSupport
#' @name     getModelWithSupport.LatentForests
#' @export
setMethodS3("getModelWithSupport", "LatentForests", function(this, support) {
  if (length(support) != nrow(this$getAllEdges())) {
    throw("Invalid support length.")
  }
  if (is.null(this$.subModelsAsStrings)) {
    this$.subModelsAsStrings = apply(this$.subModels, 1, function(x) { paste(x, collapse="") })
  }
  return(which(this$.subModelsAsStrings == paste(support, collapse = "")))
}, appendVarArgs = F)

#' Multivariate gaussian log-likelihood.
#'
#' A private method that returns the log-likelihood of the data set with
#' setData() under a multivariate gaussian model with a given covariance matrix
#' and assumed 0 means.
#'
#' @name     logLike
#' @export
#'
#' @param this the LatentForests object.
#' @param covMat a covariance matrix.
logLike <- function(this, covMat) {
    UseMethod("logLike")
}
#' @rdname   logLike
#' @name     logLike.LatentForests
#' @export
setMethodS3("logLike", "LatentForests", function(this, covMat) {
  n = this$getNumSamples()
  tXX = this$getSamplingCovMat()
  return(
    - n / 2 * ncol(covMat) * log(2 * pi)
    - n / 2 * as.numeric(determinant(covMat)$modulus)
    - (1 / 2) * sum(tXX * chol2inv(chol(covMat)))
  )
}, appendVarArgs = F, private = T)

#' EM-algorithm for latent forests.
#'
#' Uses the EM-algorithm (with multiple random restarts) to compute an
#' approximate maximum likelihood estimate for a given latent forest model.
#'
#' @name     emMain
#' @export
#'
#' @param this the LatentForests object.
#' @param model the model for which to compute the approximate MLE.
#' @param starts the number of random restarts.
#' @param maxIter the maximum number of iterations to complete in the algorithm.
#' @param tol the tolerance to use a convergence criterion.
emMain <- function(this, model, starts, maxIter, tol) {
    UseMethod("emMain")
}
#' @rdname   emMain
#' @name     emMain.LatentForests
#' @export
setMethodS3("emMain", "LatentForests", function(this, model, starts = 5,
                                                maxIter = 1000, tol = 1e-4) {
  bestLogLike <- -Inf
  n = this$getNumSamples()
  numVertices = this$getNumVertices()
  support = this$getSupport(model)
  numLeaves = this$getNumLeaves()
  if (numLeaves == 1) {
    return(list(logLike = this$logLike(matrix(1)), covMat = matrix(1)))
  } else if (numLeaves == 2) {
    if (sum(support) == 0) {
      return(list(logLike = this$logLike(diag(2)), covMat = diag(2)))
    } else {
      covMat = cor(this$getData())
      return(list(logLike = this$logLike(covMat), covMat = covMat))
    }
  }

  for (run in 1:starts) {
    ## Initializing correlations to be Uniform(.2,.9)
    edgeCorrelations = (runif(length(support), 0.2, .9)) * support
    curCovMat = this$getCovMat(edgeCorrelations)

    curLogLike = this$logLike(curCovMat[1:numLeaves, 1:numLeaves, drop = F])

    conv = FALSE
    iter = 1
    while (conv == FALSE & iter < maxIter) {
      curCovMat = this$emSteps(support, curCovMat)
      if (iter < 10 || iter %% 5 == 0) {
        nextLogLike = this$logLike(curCovMat[1:numLeaves, 1:numLeaves, drop = F])
        if (1 - nextLogLike / curLogLike < tol) {
          conv = TRUE
        }
        curLogLike = nextLogLike
      }
      iter = iter + 1
    }

    if (iter >= maxIter) {
      print("Maximum EM Iterations used!")
    }
    if (curLogLike > bestLogLike) {
      bestLogLike = curLogLike
      bestCovMat = curCovMat
    }
  }
  return(list(logLike = bestLogLike, covMat = bestCovMat))
}, appendVarArgs = F)

#' Create a covariance matrix.
#'
#' Creates a covariance matrix for the latent forest model where edge
#' correlations are given. Here edge correlations are given as a vector and
#' correspond (in order) to the edges returned by this$getAllEdges().
#'
#' @name     getCovMat
#' @export
#'
#' @param this the LatentForests object.
#' @param edgeCorrelations the edge correlations in a numeric vector.
getCovMat <- function(this, edgeCorrelations) {
    UseMethod("getCovMat")
}
#' @rdname   getCovMat
#' @name     getCovMat.LatentForests
#' @export
setMethodS3("getCovMat", "LatentForests", function(this, edgeCorrelations) {
  v = this$getNumVertices()
  E = this$getAllEdges()

  if (nrow(E) == 0) {
    return(diag(v))
  }

  Lam = matrix(0, v, v)
  U = diag(v)

  for (i in 1:length(edgeCorrelations)) {
    e1 = E[i, 1]
    e2 = E[i, 2]
    Lam[e1, e2] = edgeCorrelations[i]
    U[e2, e2] = 1 - edgeCorrelations[i] ^ 2
  }
  M = solve(diag(v) - Lam)
  return(t(M) %*% U %*% M)
}, appendVarArgs = F)

#' One EM-iteration.
#'
#' A private method that performs a single iteration of the EM-algorithm, this
#' is a helper function for emMain method.
#'
#' @name     emSteps
#' @export
#'
#' @param this the LatentForests object.
#' @param support the support of the model.
#' @param S the current covariance matrix.
emSteps <- function(this, support, S) {
    UseMethod("emSteps")
}
#' @rdname   emSteps
#' @name     emSteps.LatentForests
#' @export
setMethodS3("emSteps", "LatentForests", function(this, support, S) {
  tXX = this$getSamplingCovMat()
  E = this$getAllEdges()
  v = nrow(S) # Num vertices
  m = nrow(tXX) # Num leaves
  n = this$getNumSamples()

  SmmInvtXX = solve(S[1:m, 1:m, drop = F], tXX)
  Sigma11 = 1 / n * tXX
  Sigma12 = 1 / n * t(S[(m + 1):v, 1:m, drop = F] %*% SmmInvtXX)

  SmmInvSmv = solve(S[1:m, 1:m, drop = F], S[1:m, (m + 1):v, drop = F])
  schurComplement = S[(m + 1):v, (m + 1):v, drop = F] - S[(m + 1):v, 1:m, drop = F] %*% SmmInvSmv
  Sigma22 = schurComplement + 1 / n * S[(m + 1):v, 1:m, drop = F] %*% SmmInvtXX %*% SmmInvSmv
  Sigma = rbind(cbind(Sigma11, Sigma12), cbind(t(Sigma12), Sigma22))

  edgeCorrelations = rep(0, length(support))
  if (nrow(E) > 0) {
    for (i in 1:(nrow(E))) {
      if (support[i] == 1) {
        e1 = E[i, 1]
        e2 = E[i, 2]
        edgeCorrelations[i] = Sigma[e1, e2] / sqrt(Sigma[e1, e1] * Sigma[e2, e2])
      }
    }
  }
  return(this$getCovMat(edgeCorrelations))
}, appendVarArgs = F, private = T)
