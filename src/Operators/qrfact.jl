



type QROperator{CO,MT,T} <: Operator{T}
    R::CO
    H::MT # Contains the Householder reflections
    ncols::Int   # number of cols already upper triangularized
end

QROperator(R::CachedOperator,H::AbstractArray,ncs::Int) =
    QROperator{typeof(R),typeof(H),eltype(H)}(R,H,ncs)

for OP in (:domainspace,:rangespace)
    @eval $OP(QR::QROperator) = $OP(QR.R)
end

getindex(QR::QROperator,k::Integer,j::Integer) = QR.R.op[k,j]



immutable QROperatorR{QRT,T} <: Operator{T}
    QR::QRT
end

QROperatorR(QR) = QROperatorR{typeof(QR),eltype(QR)}(QR)
domainspace(R::QROperatorR) = domainspace(R.QR)
rangespace(R::QROperatorR) = ℓ⁰

function getindex(R::QROperatorR,k::Integer,j::Integer)
    if j < k
        zero(eltype(R))
    else
        resizedata!(R.QR,:,j)
        R.QR.R[k,j]
    end
end

bandinds(R::QROperatorR) = 0,bandinds(R.QR.R,2)

immutable QROperatorQ{QRT,T} <: Operator{T}
    QR::QRT
end

QROperatorQ(QR) = QROperatorQ{typeof(QR),eltype(QR)}(QR)


domainspace(Q::QROperatorQ) = ℓ⁰
rangespace(Q::QROperatorQ) = rangespace(Q.QR)

getindex(Q::QROperatorQ,k::Integer,j::Integer) = (Q'*eltype(Q)[zeros(k-1);1])[j]

function getindex(QR::QROperator,d::Symbol)
    d==:Q && return QROperatorQ(QR)
    d==:R && return QROperatorR(QR)

    error("Symbol not recognized")
end


# override for custom data types
QROperator{T,AM<:AbstractMatrix}(R::CachedOperator{T,AM}) =
    error("Cannot create a QR factorization for $(typeof(R))")


function Base.qrfact!(A::CachedOperator;cached::Int=0)
    QR = QROperator(A)
    if cached ≠ 0
        resizedata!(QR,:,cached)
    end
    QR
end

doc"""
    qrfact(A::Operator)

returns a cached QR factorization of the Operator `A`.  The result `QR`
enables solving of linear equations: if `u=QR\b`, then `u`
approximately satisfies `A*u = b`.
"""
function Base.qrfact(A::Operator;cached::Int=0)
    if isambiguous(domainspace(A)) || isambiguous(rangespace(A))
        throw(ArgumentError("Only non-ambiguous operators can be factorized."))
    end
    qrfact!(cache(A;padding=true);cached=cached)
end

function Base.qr(A::Operator)
    QR = qrfact(A)
    QR[:Q],QR[:R]
end

for OP in (:(Base.qrfact),:(Base.qr))
    @eval $OP{OO<:Operator}(A::Array{OO}) = $OP(interlace(A))
end


function Base.det(R::QROperatorR;maxiterations::Int=10_000)
    QR = R.QR
    RD = R.data
    resizedata!(QR,:,1)
    ret = -RD[1,1]
    k = 2
    while abs(abs(RD[k-1,k-1])-1) > eps(eltype(A))
        resizedata!(QR,:,k)
        ret *= -RD[k,k]
        k+=1
        k > maxiterations && error("Determinant unlikely to converge after 10_000 iterations.")
    end

    ret
end
Base.det(QR::QROperatorQ) = 1

Base.det(QR::QROperator) = det(QR[:R])
Base.det(A::Operator) = det(qrfact(A))




## Multiplication routines


# Q

At_mul_B_coefficients{T<:Real}(A::QROperatorQ{T},B::Union{Vector{T},Matrix{T}}) = Ac_mul_B(A,B)

Ac_mul_B_coefficients(A::QROperatorQ,B::Vector;tolerance=eps(eltype(A))/10,maxlength=1000000) =
        Ac_mul_Bpars(A,B,tolerance,maxlength)

Ac_mul_B_coefficients{QR,T,V<:Number}(A::QROperatorQ{QR,T},B::AbstractVector{V};opts...) =
    Ac_mul_B_coefficients(A,Vector{T}(B);opts...)

Base.Ac_mul_B(A::QROperatorQ,b;kwds...) =
    Fun(domainspace(A),Ac_mul_B_coefficients(A,coefficients(b,rangespace(A));kwds...))


linsolve_coefficients(A::QROperatorQ,B;opts...) = Ac_mul_B_coefficients(A,B;opts...)
linsolve(A::QROperatorQ,B;opts...) = Ac_mul_B(A,B;opts...)


# R
function linsolve_coefficients(R::QROperatorR,b::Vector)
    if length(b) > R.QR.ncols
        # upper triangularize columns
        resizedata!(R.QR,:,length(b))
    end
    trtrs!(Val{'U'},R.QR.R,copy(b))
end

linsolve(R::QROperatorR,b::Fun{SequenceSpace};kwds...) =
    Fun(domainspace(R),linsolve_coefficients(R,b.coefficients;kwds...))
linsolve(A::QROperatorR,b::Fun;kwds...) = error("linsolve not implement for $(typeof(b)) right-hand sides")
linsolve(A::QROperatorR,b;kwds...) = linsolve(A,Fun(b);kwds...)



# QR

linsolve_coefficients{CO,MT,T<:Real}(QR::QROperator{CO,MT,T},b::Vector{T};kwds...) =
    linsolve_coefficients(QR[:R],Ac_mul_B_coefficients(QR[:Q],b;kwds...))
linsolve_coefficients{CO,MT,T<:Complex}(QR::QROperator{CO,MT,T},b::Vector{T};kwds...) =
    linsolve_coefficients(QR[:R],Ac_mul_B_coefficients(QR[:Q],b;kwds...))

linsolve_coefficients{CO,MT,T,V<:Number}(QR::QROperator{CO,MT,T},b::Vector{V};kwds...) =
    linsolve_coefficients(QR,Vector{T}(b);kwds...)

linsolve_coefficients{CO,MT,T<:Real,V<:Complex}(QR::QROperator{CO,MT,T},b::Vector{V};kwds...) =
    linsolve_coefficients(QR,real(b);kwds...)+im*linsolve_coefficients(QR,imag(b);kwds...)
linsolve_coefficients{CO,MT,T<:Complex,V<:Real}(QR::QROperator{CO,MT,T},b::Vector{V};kwds...) =
    linsolve_coefficients(QR,Vector{T}(b);kwds...)


function linsolve(QR::QROperator,b::Vector{Any};kwds...)
    #TODO: PDEQR remove this is a hack
    if length(b) == 1 && isa(b[1],Fun)
        linsolve(QR,Fun(b[1],rangespace(QR));kwds...)
    else
        linsolve(QR,Fun(b,rangespace(QR));kwds...)
    end
end
function linsolve(A::QROperator,B::Matrix;kwds...)
    ds=domainspace(A)
    ret=Array(Fun{typeof(ds),promote_type(mapreduce(eltype,promote_type,B),eltype(ds))},
              1,size(B,2))
    for j=1:size(B,2)
        ret[:,j]=linsolve(A,B[:,j];kwds...)
    end
    demat(ret)
end
linsolve(A::QROperator,b;kwds...) =
    Fun(domainspace(A),linsolve_coefficients(A,coefficients(b,rangespace(A));kwds...))
