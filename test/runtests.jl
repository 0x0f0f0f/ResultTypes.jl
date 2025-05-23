using ResultTypes
using Test

struct BarError <: Exception end
struct FooError <: Exception end

@testset "ResultTypes" begin

    @testset "Result" begin
        @testset "Basic result" begin
            x = Result(2)
            @test unwrap(x) === 2
            @test_throws ErrorException unwrap_error(x)
            @test ResultTypes.iserror(x) === false
            @test x isa Result{Int,Exception}

            # on unwrapped already
            y = unwrap(x)
            @test unwrap(y) === y

            # can be broadcasted over
            x = Result(4)
            @test unwrap.(x) == 4
        end

        @testset "Result with error type" begin
            x = Result(2, DivideError)
            @test unwrap(x) === 2
            @test_throws ErrorException unwrap_error(x)
            @test ResultTypes.iserror(x) === false
            @test x isa Result{Int,DivideError}
        end

        @testset "Malformed result" begin
            x = Result{Int,Exception}(nothing, nothing)
            @test_throws ErrorException unwrap(x)
            @test_throws ErrorException unwrap_error(x)
        end
    end

    @testset "ErrorResult" begin
        @testset "Basic error" begin
            x = ErrorResult(Int, "Basic Error")
            @test_throws ErrorException unwrap(x)
            e = unwrap_error(x)
            @test isa(e, ErrorException)
            @test e.msg == "Basic Error"
            @test ResultTypes.iserror(x) === true

            # directly on exceptions
            @test ResultTypes.iserror(e)
            @test unwrap_error(e) === e
            @test !ResultTypes.iserror(2)
        end

        @testset "Empty error" begin
            x = ErrorResult(Int)
            @test_throws ErrorException unwrap(x)
            e = unwrap_error(x)
            @test isa(e, ErrorException)
            @test ResultTypes.iserror(x) === true
            @test x isa Result{Int,ErrorException}

            x = ErrorResult()
            @test_throws ErrorException unwrap(x)
            e = unwrap_error(x)
            @test isa(e, ErrorException)
            @test ResultTypes.iserror(x) === true
            @test x isa Result{Any,ErrorException}
        end

        @testset "Typed Error" begin
            x = ErrorResult(Int, DivideError())
            @test_throws DivideError unwrap(x)
            @test isa(unwrap_error(x), DivideError)
            @test ResultTypes.iserror(x) === true
            @test x isa Result{Int,DivideError}
        end
    end

    @testset "Convert" begin
        @testset "From Result" begin
            x = Result(2)
            @test unwrap(Int, x) === 2
            @test unwrap(Float64, x) === 2.0
            @test_throws MethodError unwrap(String, x)
        end

        @testset "From ErrorResult" begin
            x = ErrorResult(Int, "Foo")
            @test_throws ErrorException unwrap(Int, x)
        end

        @testset "To Result" begin
            x = convert(Result{Int,ErrorException}, 2.0)
            @test unwrap(x) === 2
            @test isa(x, Result{Int,ErrorException})
        end

        @testset "To ErrorResult" begin
            x = convert(Result{Int,DivideError}, DivideError())
            @test unwrap_error(x) == DivideError()
            @test isa(x, Result{Int,DivideError})
        end

        @testset "Result to Result" begin
            r = Result{Int,DivideError}(DivideError())
            x = convert(Result{Int,DivideError}, r)
            @test r == x
            @test r === x

            r = Result{Int,ErrorException}(2)
            x = convert(Result{Int,ErrorException}, r)
            @test r == x

            r = Result{Int,KeyError}(KeyError("foo"))
            x = convert(Result{Real,Exception}, r)
            @test x isa Result{Real,Exception}
            @test_throws KeyError unwrap(x)

            r = Result{Int,KeyError}(2)
            x = convert(Result{Real,Exception}, r)
            @test x isa Result{Real,Exception}
            @test unwrap(x) == 2
        end

        @testset "Promote" begin
            @test eltype([Result(2), ErrorResult(Int, DivideError())]) == Result{Int,Exception}
            @test eltype([Result(2), ErrorResult(DivideError())]) == Result{Any,Exception}
            @test eltype([Result(2.0), ErrorResult(Int, KeyError(:foo))]) == Result{Float64,Exception}
            @test eltype([Result(2.0, KeyError), ErrorResult(Int, KeyError(:foo))]) == Result{Float64,KeyError}

            # only for coverage, this is called above
            @test promote_rule(Result{Float64,Exception}, Result{Int,KeyError}) == Result{Float64,Exception}
        end

        @testset "Ambiguities" begin
            ambs = filter(Test.detect_ambiguities(Base, ResultTypes)) do amb
                undeprecated = all(amb) do m
                    # method is deprecated, here or in Base
                    m.file != Symbol("deprecated.jl")
                end

                ours = any(amb) do m
                    m.module == ResultTypes
                end

                undeprecated && ours
            end

            @test isempty(ambs)
        end

        @testset "Specializations" begin
            AnyRes = Result{Any,Exception}
            struct MyT end

            convert(AnyRes, MyT())
            method = only(methods(convert, Tuple{Type{AnyRes},MyT}))
            specs = method.specializations
            specs_v = method.specializations isa Core.MethodInstance ? [specs] : collect(method.specializations)
            @test only(filter(!isnothing, specs_v)).specTypes ==
                  Tuple{typeof(convert),Type{AnyRes},Any}
        end
    end

    @testset "Return" begin
        let
            function foo(x::Int, y::Int)::Result{Int,DivideError}
                try
                    return div(x, y)
                catch e
                    return e
                end
            end

            x = foo(3, 2)
            @test isa(x, Result{Int,DivideError})
            @test unwrap(x) === 1

            y = foo(1, 0)
            @test isa(y, Result{Int,DivideError})
            @test unwrap_error(y) == DivideError()
        end
    end

    @testset "@try" begin
        Base.convert(::Type{FooError}, ::BarError) = FooError()

        function isbar(x)::Result{Bool,BarError}
            x == "foo" && return BarError()
            return x == "bar"
        end

        function foo(x)::Result{Int,FooError}
            bar = @try isbar(x)
            return bar ? 42 : 13
        end

        foobar = foo("bar")
        @test isa(foobar, Result{Int,FooError})
        @test unwrap(foobar) === 42

        foofoo = foo("foo")
        @test isa(foofoo, Result{Int,FooError})
        @test unwrap_error(foofoo) === FooError()

        football = foo("tball")
        @test isa(football, Result{Int,FooError})
        @test unwrap(football) === 13

        function foo2(x)::Result{Int,ErrorException}
            bar = @try(isbar(x), ErrorException("Got a BarError"))
            return bar ? 43 : 14
        end

        foobar = foo2("bar")
        @test isa(foobar, Result{Int,ErrorException})
        @test unwrap(foobar) === 43

        foofoo = foo2("foo")
        @test isa(foofoo, Result{Int,ErrorException})
        @test unwrap_error(foofoo) === ErrorException("Got a BarError")

        football = foo2("tball")
        @test isa(football, Result{Int,ErrorException})
        @test unwrap(football) === 14
    end

    @testset "Show" begin
        @testset "Result" begin
            x = Result(2)

            @test isa(string(x), String)
        end

        @testset "ErrorResult" begin
            x = ErrorResult(Int, "Basic Error")
            @test isa(string(x), String)
        end
    end

end

include("safebase.jl")
