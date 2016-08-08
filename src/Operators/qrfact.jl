



type QROperator{CO,T} <: Operator{T}
    R::CO
    H::Matrix{T} # Contains the Householder reflections
    ncols::Int   # number of cols already upper triangularized
end

for OP in (:domainspace,:rangespace)
    @eval $OP(QR::QROperator) = $OP(QR.R)
end

getindex(QR::QROperator,k::Integer,j::Integer) = (QR[:Q]*QR[:R])[k,j]



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

getindex(Q::QROperatorQ,k::Integer,j::Integer) = (Q'*[zeros(k-1);1])[j]

function getindex(QR::QROperator,d::Symbol)
    d==:Q && return QROperatorQ(QR)
    d==:R && return QROperatorR(QR)

    error("Symbol not recognized")
end


function QROperator{T}(R::CachedOperator{T,AlmostBandedMatrix{T}})
    M = R.data.bands.l+1   # number of diag+subdiagonal bands
    H = Array(T,M,100)
    QROperator(R,H,0)
end

function QROperator{T}(R::CachedOperator{T,BandedMatrix{T}})
    M = R.data.l+1   # number of diag+subdiagonal bands
    H = Array(T,M,100)
    QROperator(R,H,0)
end

function QROperator{T}(R::CachedOperator{T,Matrix{T}})
    error("Cannot create a QR factorization for $R")
end


function Base.qrfact(A::Operator)
    if isambiguous(domainspace(A)) || isambiguous(rangespace(A))
        throw(ArgumentError("Only non-ambiguous operators can be factorized."))
    end
    QROperator(cache(A;padding=true))
end

function Base.qr(A::Operator)
    QR = qrfact(A)
    QR[:Q],QR[:R]
end

for OP in (:(Base.qrfact),:(Base.qr))
    @eval $OP{OO<:Operator}(A::Array{OO}) = $OP(InterlaceOperator(A))
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

linsolve{CO,T<:Real}(QR::QROperator{CO,T},b::Vector{T};kwds...) =
    Fun(QR[:R]\Ac_mul_B(QR[:Q],b;kwds...),domainspace(QR))
linsolve{CO,T<:Complex}(QR::QROperator{CO,T},b::Vector{T};kwds...) =
    Fun(QR[:R]\Ac_mul_B(QR[:Q],b;kwds...),domainspace(QR))

linsolve{CO,T,V<:Number}(QR::QROperator{CO,T},b::Vector{V};kwds...) =
    linsolve(QR,Vector{T}(b);kwds...)

linsolve{CO,T<:Real,V<:Complex}(QR::QROperator{CO,T},b::Vector{V};kwds...) =
    linsolve(QR,real(b);kwds...)+im*linsolve(QR,imag(b);kwds...)
linsolve{CO,T<:Complex,V<:Real}(QR::QROperator{CO,T},b::Vector{V};kwds...) =
    linsolve(QR,Vector{T}(b);kwds...)



linsolve(QR::QROperator,b::Fun;kwds...) = linsolve(QR,coefficients(b,rangespace(QR));kwds...)
function linsolve(QR::QROperator,b::Vector{Any};kwds...)
    #TODO: PDEQR remove this is a hack
    if length(b) == 1 && isa(b[1],Fun)
        linsolve(QR,Fun(b[1],rangespace(QR));kwds...)
    else
        linsolve(QR,Fun(b,rangespace(QR));kwds...)
    end
end
linsolve{FF<:Fun}(QR::QROperator,b::Vector{FF};kwds...) = linsolve(QR,Fun(b,rangespace(QR));kwds...)
function linsolve(A::QROperator,B::Matrix;kwds...)
    ds=domainspace(A)
    ret=Array(Fun{typeof(ds),promote_type(eltype(eltype(B)),eltype(ds))},1,size(B,2))
    for j=1:size(B,2)
        ret[:,j]=linsolve(A,B[:,j];kwds...)
    end
    demat(ret)
end
linsolve(A::QROperator,b;kwds...) = linsolve(A,Fun(b);kwds...)

Base.Ac_mul_B(A::QROperatorQ,b::Vector{Any};kwds...) = Ac_mul_B(A,Fun(b,rangespace(A));kwds...)
Base.Ac_mul_B{FF<:Fun}(A::QROperatorQ,b::Vector{FF};kwds...) = Ac_mul_B(A,Fun(b,rangespace(A));kwds...)

Base.At_mul_B{T<:Real}(A::QROperatorQ{T},B::Union{Vector{T},Matrix{T}}) = Ac_mul_B(A,B)

Base.Ac_mul_B{QR,T<:BlasFloat}(A::QROperatorQ{QR,T},B::Vector{T};
                                        tolerance=eps(T)/10,maxlength=1000000) =
        Ac_mul_Bpars(A,B,tolerance,maxlength)

function Ac_mul_Bpars{QR,T<:BlasFloat}(A::QROperatorQ{QR,T},B::Vector{T},
                                        tolerance,maxlength)
    if length(B) > A.QR.ncols
        # upper triangularize extra columns to prepare for \
        resizedata!(A.QR,:,length(B)+size(A.QR.H,1)+10)
    end

    H=A.QR.H
    h=pointer(H)

    M=size(H,1)

    b=pointer(B)
    st=stride(H,2)

    sz=sizeof(T)

    m=length(B)
    Y=pad(B,m+M+10)
    y=pointer(Y)

    k=1
    yp=y
    while (k ≤ m+M || BLAS.nrm2(M,yp,1) > tolerance )
        if k > maxlength
            warn("Maximum length $maxlength reached.")
            break
        end

        if k+M-1>length(Y)
            pad!(Y,2*(k+M))
            y=pointer(Y)
        end
        if k > A.QR.ncols
            # upper triangularize extra columns to prepare for \
            resizedata!(A.QR,:,2*(k+M))
            H=A.QR.H
            h=pointer(H)
        end

        wp=h+sz*st*(k-1)
        yp=y+sz*(k-1)

        dt=dot(M,wp,1,yp,1)
        BLAS.axpy!(M,-2*dt,wp,1,yp,1)
        k+=1
    end
    Fun(Y,domainspace(A))  # chop off zeros
end

Base.Ac_mul_B{QR,T,V<:Number}(A::QROperatorQ{QR,T},B::AbstractVector{V};opts...) =
    Ac_mul_B(A,Vector{T}(B))

Base.Ac_mul_B{QR,T}(A::QROperatorQ{QR,T},B::Fun;opts...) =
    Ac_mul_B(A,coefficients(B,rangespace(A)))


function linsolve(R::QROperatorR,b::Vector)
    if length(b) > R.QR.ncols
        # upper triangularize columns
        resizedata!(R.QR,:,length(b))
    end
    Fun(backsubstitution!(R.QR.R,copy(b)),domainspace(R))
end

linsolve(R::QROperatorR,b::Fun{SequenceSpace};kwds...) = linsolve(R,b.coefficients;kwds...)
linsolve(A::QROperatorR,b::Fun;kwds...) = error("linsolve not implement for $(typeof(b)) right-hand sides")
linsolve(A::QROperatorR,b;kwds...) = linsolve(A,Fun(b);kwds...)
