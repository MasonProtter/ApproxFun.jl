export newton, linop

struct DualFun{F,T}
    f::F
    J::T
end
DualFun(f::Fun) = DualFun(f,eye(space(f)))


domain(df::DualFun) = domain(df.f)

differentiate(d::DualFun) = DualFun(d.f',Derivative(rangespace(d.J))*d.J)
integrate(d::DualFun) = DualFun(integrate(d.f),Integral(rangespace(d.J))*d.J)
function cumsum(d::DualFun)
    Q=Integral(rangespace(d.J))*d.J
    DualFun(cumsum(d.f),(I-Evaluation(rangespace(Q),first))*Q)
end


transpose(d::DualFun)=differentiate(d)

^(d::DualFun,k::Integer)=DualFun(d.f^k,k*d.f^(k-1)*d.J)

# from DualNumbers
for (funsym, exp) in Calculus.symbolic_derivatives_1arg()
    @eval function $(funsym)(z::DualFun)
        x = z.f
        xp = z.J
        DualFun($(funsym)(x),$exp*xp)
    end
end

for OP in (:+,:-)
    @eval begin
        $OP(a::DualFun,b::Union{Number,Fun}) = DualFun($OP(a.f,b),a.J)
        $OP(a::Union{Number,Fun},b::DualFun) = DualFun($OP(a,b.f),$OP(b.J))
        $OP(a::DualFun,b::DualFun) = DualFun($OP(a.f,b.f),$OP(a.J,b.J))
    end
end
-(a::DualFun)=DualFun(-a.f,-a.J)

*(a::Union{Number,Fun},b::DualFun)=DualFun(a*b.f,a*b.J)
*(a::DualFun,b::Union{Number,Fun})=DualFun(b*a.f,b*a.J)
*(a::DualFun,b::DualFun)=DualFun(a.f*b.f,a.f*b.J+b.f*a.J)

/(a::Union{Number,Fun},b::DualFun)=DualFun(a/b.f,-a/b.f^2*b.J)
/(a::DualFun,b::Union{Number,Fun})=DualFun(a.f/b,a.J/b)
/(a::DualFun,b::DualFun)=DualFun(a.f/b.f,a.J/b.f-a.f/b.f^2*b.J)


(d::DualFun)(x) = DualFun(d.f(x),Evaluation(rangespace(d.J),x)*d.J)
first(d::DualFun) = DualFun(first(d.f),Evaluation(rangespace(d.J),first)*d.J)
last(d::DualFun) = DualFun(last(d.f),Evaluation(rangespace(d.J),last)*d.J)

jacobian(d::DualFun)=d.J


promote_rule(::Type{DF},::Type{T}) where {DF<:DualFun,T<:Number}=DualFun
convert(::Type{DualFun},b::Number) = DualFun(b,0)



function linop(f::Function,ds::Space)
    if (isgeneric(f) && applicable(f,0)) || (!isgeneric(f)&&arglength(f)==1)
        df=f(DualFun(zeros(ds)))
    elseif (isgeneric(f) && applicable(f,0,0)) || (!isgeneric(f)&&arglength(f)==2)
        df=f(Fun(ds),DualFun(zeros(ds)))
    else
        error("Not implemented")
    end

    if isa(df,Array)
        map(u->u.J,df)
    else
        df.J
    end
end

linop(f::Function,d) = linop(f,Space(d))
linop(f::Function) = linop(f,Chebyshev())  #TODO: UnsetSpace



# full operator should be
# N=u->[B*u-bcs;...]
function newton(N,u0::Fun;maxiterations=15,tolerance=1E-15)
    u=u0
    err=Inf
    for k=1:maxiterations
        DF=N(DualFun(u))
        J=map(jacobian,DF)
        F=map(d->d.f,DF)
        unew=u-J\F
        err=norm(unew-u)
        if err≤10tolerance
            return unew
        else
            u=chop(unew,tolerance)
        end
    end
    @warn "Maximum number of iterations $maxiterations reached, with approximate accuracy of $err."
    return u
end


newton(N,d::Domain;opts...) =
    newton(N,zeros(d);opts...)

newton(N,d;opts...) =
    newton(N,Domain(d);opts...)
