# sBIC Package

## Purpose

This package allows you to compute the singilar Bayesian information criterion as described in Drton and Plummer (2017) for collections of the following model types:

1. Binomial mixtures
2. Gaussian mixtures
3. Latent class analysis
4. Gaussian latent forests
5. Reduced rank regression
6. Factor analysis


All of these models, excluding Gaussian latent forests, are described in the above paper. For details regardings the use of the sBIC with Gaussian latent forests see Drton et al (2014).

## Object oriented approach

This package makes extensive use of the `R.oo` package (Bengtsson 2003) which allows for the use
of some object oriented principles in R. While not strictly necessary to use this package it may be helpful to read sections 1 and 2 of Bengstsson (2003) which serve as an introduction to R.oo.

An important consequence of the use of `R.oo` is that objects in the `sBIC` package use call by reference semantics and are modified by calling their associated methods.

## Example

Each collection of models is defined as its own class.  As an example for how to use the package we will compute the sBIC for a collection of Gaussian mixture models with at most 8 components:

```{r}
set.seed(123)
```

Create an object representing a collection of Gaussian mixture models with at most 8 components in 2 dimensions.

```{r}
library(sBIC)
gms = GaussianMixtures(maxNumComponents = 8, dim = 2, restarts = 100)
```

Generate some simulated data, a mixture of 3 bivariate normals.

```{r}
library(MASS)
n = 175
class = sample(0:2, n, replace = TRUE)
X = (class == 0) * mvrnorm(n, mu = c(0, 0), Sigma = diag(2)) +
    (class == 1) * mvrnorm(n, mu = c(2.5, 2.5), Sigma = diag(1.3, 2)) +
    (class == 2) * mvrnorm(n, mu = c(-3, 2.5), Sigma = diag(1.2, 2))
``` 

Compute the sBIC on the mixture models with the randomly generated data. 

```{r}
sBIC(X, gms)
```

Notice that the BIC too strongly penalizes the (true) model with 3 components.

## References

* Bengtsson, H. (2003)The R.oo package - Object-Oriented Programming with References Using Standard R Code, Proceedings of the 3rd   International Workshop on Distributed Statistical Computing (DSC 2003), ISSN 1609-395X, Hornik, K.; Leisch, F. & Zeileis, A. (eds.) URL https://www.r-project.org/conferences/DSC-2003/Proceedings/Bengtsson.pdf
* Drton M, Lin S, Weihs L and  Zwiernik P. (2014) Marginal likelihood and model selection for Gaussian latent tree and forest models. arXiv preprint arXiv:1412.8285.
* Drton M. and Plummer M. (2017), A Bayesian information criterion for singular models. J. R. Statist. Soc. B; 79: 1-38. Also available as arXiv preprint arXiv:1309.0911 