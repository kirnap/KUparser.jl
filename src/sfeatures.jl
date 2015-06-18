# Sparse compound features are specified using a vector of feature
# names, e.g. ["s0w", "s0p"]

typealias SFeature{T<:String} Vector{T}

# Each string specifies a particular feature and has the form:
#   [sn]\d?([hlr]\d?)*[wpdLabAB]
# 
# The meaning of each letter is below.  In the following i is a single
# digit integer which is optional if the default value is used:
#
# si: i'th stack word, default i=0 means top
# ni: i'th buffer word, default i=0 means first
# hi: i'th degree head, default i=1 means direct head
# li: i'th leftmost child, default i=1 means the leftmost child 
# ri: i'th rightmost child, default i=1 means the rightmost child
# w: word
# p: postag
# d: distance to the right.  e.g. s1d is s0s1 distance, s0d is s0n0
#    distance.  encoding: 1,2,3,4,5-10,10+ (from ZN11)
# L: dependency label (0 is ROOT or NONE)
# a: number of left children.  following ZN11, any number is allowed.
# b: number of right children.  following ZN11, any number is allowed.
# A: set of left dependency labels
# B: set of right dependency labels

# Sparse compound feature vectors are specified using a vector of
# SFeature's (possibly headed by a hash?)

typealias SFvec Vector

# It does not cost anything to increase the height of a
# SparseMatrixCSC, so we'll just use a large fixed height
# (bad idea?)

SFmax = (1<<30)
flen(p::Parser, s::Sentence, feats::SFvec)=SFmax

# We will also use a global dictionary to look up feature-value pairs
# (another bad idea?) (especially for multi-threaded operation!)

SFhash = Dict{Any,Int}()

# To construct a sparse feature vector, we go through the compound
# features in SFvec in order, lookup their values using features1, get
# the index of the key-value pair from SFhash, and set the
# corresponding entry in the feature hash x to 1.

function features(p::Parser, s::Sentence, feats::SFvec,
                  x::AbstractSparseArray=spzeros(wtype(s),flen(p,s,feats),1), 
                  xcol::Integer=1)
    x[:,xcol] = zero(eltype(x)) # how fast is this?
    for f in feats
        fv = (f, map(x->features1(p, s, x), f)) # how fast is this?
        idx = get!(SFhash, fv, 1+length(SFhash))
        @assert idx < SFmax
        x[idx, xcol] = one(eltype(x)) # how fast is this?
    end
    return x
end

# Here is where the actual feature lookup happens.  Similar to the
# dense lookup.  But does not have to convert everything to a number,
# can return strings etc.  Returns 'nothing' if target word does not
# exist or the feature is not available.

function features1(p::Parser, s::Sentence, f::String)
    @assert in(f[1], "sn") "feature string should start with [sn]"
    (i,n) = isdigit(f[2]) ? (f[2] - '0', 3) : (0, 2) # target index and start of feature spec
    (a,d) = (0,0)           # target word position and right distance
    if ((f[1] == 's') && (p.sptr - i >= 1))
        a = p.stack[p.sptr - i]                    # target word is in the stack
        d = (i>0 ? (p.stack[p.sptr - i + 1] - a) : # distance between two stack words
             p.wptr <= p.nword ? (p.wptr - a) : 0) # distance between top of stack and top of buffer, 0 if buffer empty
    elseif ((f[1] == 'n') && (p.wptr + i <= p.nword))
        a = p.wptr + i          # target word is in the buffer
    end
    (a == 0) && (return nothing) # target word invalid

    # if next character is in "hlr" treat current (a) as an anchor and
    # find the appropriate head, left, right as the actual target
    while (fn=f[n];in(fn, "hlr"))
        d = 0                   # only stack words get distance
        (i,n) = isdigit(f[n+1]) ? (f[n+1] - '0', n+2) : (1, n+1)
        @assert i > 0 "hlr indexing is one based" # l1 is the leftmost child, h1 is the direct head etc.
        a == 0 && break
        if fn == 'l'
            @assert (a <= p.wptr) "buffer words other than n0 do not have ldeps"
            j = p.lcnt[a] - i + 1 # leftmost child at highest index
            a = (j > 0) ? p.ldep[a,j] : 0
        elseif fn == 'r'
            @assert (a < p.wptr) "buffer words do not have rdeps"
            j = p.rcnt[a] - i + 1
            a = (j > 0) ? p.rdep[a,j] : 0
        else # if fn == 'h'
            for j=1:i
                a = p.head[a]
                a == 0 && break
            end
        end
    end
    (a == 0) && (return nothing)

    # At this point (a) should be the target word position and we
    # should only have one character left specifying a feature
    @assert n == length(f)
    fn = f[n]
    ((fn == 'w') ? s.form[a] :
     (fn == 'p') ? s.postag[a] :
     (fn == 'd') ? (d>10 ? 6 : d>5 ? 5 : d>0 ? d : nothing) :
     (fn == 'L') ? p.deprel[a] :
     (fn == 'a') ? p.lcnt[a] :
     (fn == 'b') ? p.rcnt[a] :
     (fn == 'A') ? unique(sort(p.deprel[vec(p.ldep[a,1:p.lcnt[a]])])) :
     (fn == 'B') ? unique(sort(p.deprel[vec(p.rdep[a,1:p.rcnt[a]])])) :
     error("Unknown feature letter $fn"))
end