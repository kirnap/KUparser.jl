using KUparser, KUnet, HDF5, JLD, ArgParse, Compat, CUDArt
VERSION < v"0.4-" && eval(Expr(:using,:Dates))

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "datafiles"
        help = "JLD files for input: first one will be used for training"
        nargs = '+'
        required = true
        "--out"
        help = "JLD file for output trained network"
        default = ""
        "--nogpu"
        help = "Do not use gpu"
        action = :store_true
        "--parser"
        help = "Parsing algorithm to use: g(reedy)parser, b(eam)parser, or o(racle)parser for static training"
        default = "oparser"
        "--arctype"
        help = "Move set to use: ArcEager{R1,13}, ArcHybrid{R1,13}"
        default = "ArcEager13"
        "--feats"
        help = "Features to use from KUparser.Flist"
        default = "tacl13hybrid"
        "--hidden"
        help = "One or more hidden layer sizes"
        nargs = '+'
        arg_type = Int
        default = [20000]
        "--epochs"
        help = "Minimum number of epochs to train"
        arg_type = Int
        default = 100
        "--pepochs"
        help = "Number of epochs between parsing"
        arg_type = Int
        default = 1

        # This version does not work with multi cpu
        # "--ncpu"
        # help = "Number of workers for multithreaded parsing"
        # arg_type = Int
        # default = 12

        "--pbatch"
        help = "Minibatch size for parsing"
        arg_type = Int
        default = 2000
        "--tbatch"
        help = "Minibatch size for training"
        arg_type = Int
        default = 128
        "--nbeam"
        help = "Beam size for bparser"
        arg_type = Int
        default = 10
        "--adagrad"
        help = "If nonzero apply adagrad using arg as epsilon"
        arg_type = Float32
        nargs = '+'
        default = [1f-8]
        "--dropout"
        help = "Dropout probability"
        arg_type = Float32
        nargs = '+'
        default = [0.2f0, 0.7f0]
        "--l1reg"
        help = "L1 regularization parameter"
        arg_type = Float32
        nargs = '+'
        "--l2reg"
        help = "L2 regularization parameter"
        arg_type = Float32
        nargs = '+'
        "--learningRate"
        help = "Learning rate"
        arg_type = Float32
        nargs = '+'
        default = [2f-2]
        "--maxnorm"
        help = "If nonzero upper limit on weight matrix row norms"
        arg_type = Float32
        nargs = '+'
        "--momentum"
        help = "Momentum"
        arg_type = Float32
        nargs = '+'
        "--nesterov"
        help = "Apply nesterov's accelerated gradient"
        arg_type = Float32
        nargs = '+'
        "--seed"
        help = "Random number seed (-1 leaves the default seed)"
        arg_type = Int
        default = -1
    end
    args = parse_args(s)
    for (arg,val) in args
        print("$arg:$val ")
    end
    println("")
    return args
end


function main()
    args = parse_commandline()
    KUnet.gpu(!args["nogpu"])
    args["nogpu"] && blas_set_num_threads(20)
    args["seed"] >= 0 && (srand(args["seed"]); KUnet.gpuseed(args["seed"]))

    data = Corpus[]
    deprel = nothing
    ndeps = 0
    for f in args["datafiles"]
        @date d=load(f)
        push!(data, d["corpus"])
        if deprel == nothing
            deprel = d["deprel"]
            ndeps = length(deprel)
        else
            @assert deprel == d["deprel"]
        end
    end

    feats = eval(parse("Flist."*args["feats"]))
    pt = eval(parse(args["arctype"]))
    s1 = data[1][1]
    p1 = pt(wcnt(s1),length(deprel))
    xrows=KUparser.flen(p1, s1, feats)
    yrows=p1.nmove

    net=newnet(relu, [xrows; args["hidden"]; yrows]...)
    net[end].f=KUnet.logp
    for k in [fieldnames(UpdateParam); :dropout]
        haskey(args, string(k)) || continue
        v = args[string(k)]
        if isempty(v)
            continue
        elseif length(v)==1
            setparam!(net, k, v[1])
        else 
            @assert length(v)==length(net) "$k should have 1 or $(length(net)) elements"
            for i=1:length(v)
                setparam!(net[i], k, v[i])
            end
        end
    end
    @show net

    pa = Array(Vector{pt}, length(data))
    x = y = nothing
    for i=1:length(data)
        # Initialize training set using oparse on first corpus
        if i==1
            @date (pa[i],x,y) = oparse(pt, data[i], ndeps, feats)
            @show map(size, (pa[i], x, y))
        else
            @date pa[i] = oparse(pt, data[i], ndeps)
        end
        @show evalparse(pa[i], data[i])
    end
    accuracy = Array(Float32, length(data))
    (bestscore,bestepoch,epoch)=(0,0,0)
    
    while true
        @show epoch += 1
        @date train(net, x, y; batch=args["tbatch"], loss=KUnet.logploss, shuffle=true)
        if epoch % args["pepochs"] == 0
            for i=1:length(data)
                @show i
                @date reset!(pa[i])
                if (args["parser"] == "oparser")
                    # We never change the training set with oparser, just report accuracy
                    @date gparse(pa[i], data[i], ndeps, feats, net, args["pbatch"])
                elseif (args["parser"] == "gparser")
                    # The first corpus gives us the new training set
                    if i==1
                        @date gparse(pa[i], data[i], ndeps, feats, net, args["pbatch"], x, y)
                    else
                        @date gparse(pa[i], data[i], ndeps, feats, net, args["pbatch"])
                    end
                elseif (args["parser"] == "bparser")
                    # The first corpus gives us the new training set
                    if i==1
                        @date bparse(pa[i], data[i], ndeps, feats, net, args["nbeam"], args["pbatch"], x, y)
                    else
                        @date bparse(pa[i], data[i], ndeps, feats, net, args["nbeam"], args["pbatch"])
                    end
                else
                    error("Unknown parser "*args["parser"])
                end
                @show e = evalparse(pa[i], data[i])
                accuracy[i] = e[1]  # e[1] is UAS including punct
            end
            println("DATA:\t$epoch\t"*join(accuracy, '\t')); flush(STDOUT)

            # We look at accuracy[2] (dev score) by default,
            # accuracy[1] (trn score) if there is no dev.

            score = (length(accuracy) > 1 ? accuracy[2] : accuracy[1])

            # Update best score and save best net

            if (score > bestscore)
                @show (bestscore,bestepoch)=(score,epoch)
                !isempty(args["out"]) && save(args["out"], net)
            end

            # Quit if we have the minimum number of epochs and have
            # not made progress in the last half.
            
            (epoch >= args["epochs"]) && (epoch >= 2*bestepoch) && break

        end
    end
end

main()
