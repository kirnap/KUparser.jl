# ?? @everywhere using KUnet

# The greedy transition parser parses the sentence using the
# following:

function gparse(s::Sentence, n::Net, f::Fmat, pred::Bool=true)
    (ndims, nword) = size(s.wvec)
    p = ArcHybrid(nword)
    x = Array(eltype(s.wvec), flen(ndims, f), 1)
    y = Array(eltype(x), p.nmove, 1)
    while (v = valid(p); any(v))
        features(p, s, f, x)
        pred ? predict(n, x, y) : rand!(y)  # for testing and timing
        y[!v,:] = -Inf
        move!(p, indmax(y))
    end
    p.head
end

function gparse(c::Corpus, n::Net, f::Fmat, pred::Bool=true)
    map(s->gparse(s,n,f,pred), c)
    # for s in c; gparse(s,n,f); end # not faster than map
end

wdim(s)=size(s.wvec,1)
wcnt(s)=size(s.wvec,2)

# There are two opportunities for parallelism:
# 1. We process multiple sentences to minibatch net input.
#    This speeds up forw.

function gparse(corpus::Corpus, net::Net, fmat::Fmat, batch::Integer)
    # determine dimensions
    nsent = length(corpus)
    nword = 0; for s in corpus; nword += wcnt(s); end
    xcols = 2 * (nword - nsent)
    wvec1 = corpus[1].wvec
    wdims = size(wvec1,1)
    xrows = flen(wdims, fmat)
    xtype = eltype(wvec1)
    yrows = ArcHybrid(1).nmove

    # initialize arrays
    p = Array(ArcHybrid, nsent) 	# parsers
    v = Array(Bool, yrows, nsent)       # valid move arrays
    x = Array(xtype, xrows, xcols)      # feature vectors
    y = Array(xtype, yrows, xcols)      # predicted move scores
    z = zeros(xtype, yrows, xcols)      # mincost moves, 1-of-k encoding
    svalid = Array(Int, batch)          # indices of valid sentences in current batch
    idx = 0                             # index of last used column in x, y, z
    for s=1:nsent; p[s] = ArcHybrid(wcnt(corpus[s])); end
    xxcols = batch
    xx = similar(net[1].w, (xrows, xxcols)) # device array

    # parse corpus[b:e] in parallel
    for b = 1:batch:nsent
        e = b + batch - 1
        (e > nsent) && (e = nsent; batch = e - b + 1)
        for s=b:e
            p[s] = ArcHybrid(wcnt(corpus[s]))
            svalid[s-b+1] = s
        end
        nvalid = batch
        while true
            # Update svalid and nvalid
            nv = 0
            for i=1:nvalid
                s = svalid[i]
                vs = sub(v, :, s)
                valid(p[s], vs)
                any(vs) && (nv += 1; svalid[nv] = s)
            end
            (nv == 0) && break
            nvalid = nv

            # svalid[1:nvalid] are the indices of still valid sentences in current batch
            # Take the next move with them
            # First calculate features x[:,idx+1:idx+nvalid]
            for i=1:nvalid
                s = svalid[i]
                features(p[s], corpus[s], fmat, sub(x, :, idx + i))
            end

            # Next predict y in bulk
            (xxcols != nvalid) && (xxcols = nvalid; KUnet.free(xx); xx = similar(net[1].w, (xrows, xxcols)))
            copy!(xx, (1:xrows, 1:nvalid), x, (1:xrows, idx+1:idx+nvalid))
            yy = KUnet.forw(net, xx, false)
            copy!(y, (1:yrows, idx+1:idx+nvalid), yy, (1:yrows, 1:nvalid))

            # Finally find best moves and execute max score valid moves
            for i=1:nvalid
                s = svalid[i]
                bestmove = indmin(cost(p[s], corpus[s].head))
                z[bestmove, idx+i] = one(xtype)
                maxmove, maxscore = 0, -Inf
                for j=1:yrows
                    yj = y[j,idx+i]
                    v[j,s] && (yj > maxscore) && ((maxmove, maxscore) = (j, yj))
                end
                move!(p[s], maxmove)
            end # for i=1:nvalid
            idx = idx + nvalid
        end # while true
    end # for b = 1:batch:nsent
    KUnet.free(xx)
    h = Array(Pvec, nsent) 	# predicted heads
    for s=1:nsent; h[s] = p[s].head; end
    return h
end

# 2. We do multiple batches in parallel to utilize CPU cores.
#    This speeds up features.
#
# nworkers() gives the number of processes available

# function gparse(corpus::Corpus, net::Net; batch=128)
#     p = @parallel (vcat) for b=1:batch:length(corpus)
#         e = b + batch - 1
#         e > length(corpus) && (e = length(corpus))
#         gparse(corpus, net, b, e)
#     end
# end

# function gparse(corpus::Corpus, net::Net, b::Integer, e::Integer)
    
# end


# what if net does not get copied?
# we may overwrite fields?
# ideal would be cpu/net copied, gpu left alone
# what if net does get copied and we run out of memory


# maybe first debug the simple parser, then parallelize...
