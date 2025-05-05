# ResultTypes

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://iamed2.github.io/ResultTypes.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://iamed2.github.io/ResultTypes.jl/dev)
[![Build Status](https://travis-ci.com/iamed2/ResultTypes.jl.svg?branch=master)](https://travis-ci.com/iamed2/ResultTypes.jl)
[![Codecov](https://codecov.io/gh/iamed2/ResultTypes.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/iamed2/ResultTypes.jl)

ResultTypes provides a `Result` type which can hold either a value or an error.
This allows us to return a value or an error in a type-stable manner without throwing an exception.

## Usage

### Basic

We can construct a `Result` that holds a value:

```julia
julia> x = Result(2); typeof(x)
ResultTypes.Result{Int64,ErrorException}
```

or a `Result` that holds an error:

```julia
julia> x = ErrorResult(Int, "Oh noes!"); typeof(x)
ResultTypes.Result{Int64,ErrorException}
```

or either with a different error type:

```julia
julia> x = Result(2, DivideError); typeof(x)
ResultTypes.Result{Int64,DivideError}

julia> x = ErrorResult(Int, DivideError()); typeof(x)
ResultTypes.Result{Int64,DivideError}
```

### Exploiting Function Return Types

We can take advantage of automatic conversions in function returns (a Julia 0.5 feature):

```julia
function integer_division(x::Int, y::Int)::Result{Int, DivideError}
    if y == 0
        return DivideError()
    else
        return div(x, y)
    end
end
```

This allows us to write code in the body of the function that returns either a value or an error without manually constructing `Result` types.

```julia
julia> integer_division(3, 4)
Result(0)

julia> integer_division(3, 0)
ErrorResult(Int64, DivideError())
```

## Safe Base

The `ResultTypes.SafeBase` module contains some useful new functions and overloadings of Base Julia functions that return a `Result` type instead of throwing on error. The functions are prefixed with `safe_`, such as `safe_parse`, `safe_parse_julia`, and `safe_eval`.

## Evidence of Benefits

### Theoretical

Using the function above, we can use `@code_warntype` to verify that the compiler is doing what we desire:

```julia
julia> @code_warntype integer_division(3, 2)
Body::Result{Int64,DivideError}
2 1 ─ %1 = (y === 0)::Bool                                                                                       │╻     ==
  └──      goto #3 if not %1                                                                                     │
3 2 ─ %3 = %new(Result{Int64,DivideError}, nothing, $(QuoteNode(DivideError())))::Result{Int64,DivideError}      │╻╷    convert
  └──      return %3                                                                                             │
5 3 ─ %5 = (Base.checked_sdiv_int)(x, y)::Int64                                                                  │╻     div
  │   %6 = %new(Some{Int64}, %5)::Some{Int64}                                                                    ││╻╷╷╷  Type
  │   %7 = %new(Result{Int64,DivideError}, %6, nothing)::Result{Int64,DivideError}                               │││
  └──      return %7                                                                                             │
```

### Experimental

Suppose we have two versions of a function where one returns a value or throws an exception and the other returns a `Result` type.
We want to call the function and return the value if present or a default value if there was an error.
For this example we can use `div` and our `integer_division` function as a microbenchmark (they are too simple to provide a realistic use case).
We'll use `@noinline` to ensure the functions don't get inlined, which will make the benchmarks more comparable.

Here's our wrapping function for `div`:

```julia
@noinline function func1(x, y)
    local z
    try
        z = div(x, y)
    catch e
        z = 0
    end
    return z
end
```

and for `integer_division`:

```julia
@noinline function func2(x, y)
    r = integer_division(x, y)
    if ResultTypes.iserror(r)
        return 0
    else
        return unwrap(r)
    end
end
```

Here are some benchmark results in the average case (on one machine), using [BenchmarkTools.jl](https://github.com/JuliaCI/BenchmarkTools.jl):

```julia
julia> using BenchmarkTools, Statistics

julia> t1 = @benchmark for i = 1:10 func1(3, i % 2) end
BenchmarkTools.Trial:
  memory estimate:  0 bytes
  allocs estimate:  0
  --------------
  minimum time:     121.664 μs (0.00% GC)
  median time:      122.652 μs (0.00% GC)
  mean time:        124.350 μs (0.00% GC)
  maximum time:     388.198 μs (0.00% GC)
  --------------
  samples:          10000
  evals/sample:     1

julia> t2 = @benchmark for i = 1:10 func2(3, i % 2) end
BenchmarkTools.Trial:
  memory estimate:  0 bytes
  allocs estimate:  0
  --------------
  minimum time:     18.853 ns (0.00% GC)
  median time:      21.078 ns (0.00% GC)
  mean time:        21.183 ns (0.00% GC)
  maximum time:     275.057 ns (0.00% GC)
  --------------
  samples:          10000
  evals/sample:     997

julia> judge(mean(t2), mean(t1))
BenchmarkTools.TrialJudgement:
  time:   -99.98% => improvement (5.00% tolerance)
  memory: +0.00% => invariant (1.00% tolerance)
```

As we can see, we get a huge speed improvement without allocating any extra heap memory.

It's also interesting to look at the cost when no error occurs:

```julia
julia> t1 = @benchmark for i = 1:10 func1(3, 1) end
BenchmarkTools.Trial:
  memory estimate:  0 bytes
  allocs estimate:  0
  --------------
  minimum time:     115.060 ns (0.00% GC)
  median time:      118.042 ns (0.00% GC)
  mean time:        118.616 ns (0.00% GC)
  maximum time:     279.901 ns (0.00% GC)
  --------------
  samples:          10000
  evals/sample:     918

julia> t2 = @benchmark for i = 1:10 func2(3, 1) end
BenchmarkTools.Trial:
  memory estimate:  0 bytes
  allocs estimate:  0
  --------------
  minimum time:     28.775 ns (0.00% GC)
  median time:      30.516 ns (0.00% GC)
  mean time:        31.290 ns (0.00% GC)
  maximum time:     74.936 ns (0.00% GC)
  --------------
  samples:          10000
  evals/sample:     995

julia> judge(mean(t2), mean(t1))
BenchmarkTools.TrialJudgement:
  time:   -73.62% => improvement (5.00% tolerance)
  memory: +0.00% => invariant (1.00% tolerance)
```

It's _still faster_ to avoid `try` and use `Result`, even when the error condition is never triggered.
