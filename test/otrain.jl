using Dates
msg(x)=(println("$(now()) $x"); flush(STDOUT))
msg("Setting up workers"); 
ncpu=12
nbatch=2000
(nworkers() < ncpu) && (addprocs(ncpu - nprocs() + 1))
require("CUDArt")
@everywhere CUDArt.device((myid()-1) % CUDArt.devcount())
require("CUBLAS")
require("KUnet")
require("KUparser")

msg("Loading conllWSJToken_wikipedia2MUNK-100.jld")
using HDF5, JLD
@time @load "conllWSJToken_wikipedia2MUNK-100.jld"

evalheads(h,c)=mean(vcat(h...) .== vcat(map(s->s.head,c)...))
feats=KUparser.Flist.fv021a

if true
    msg("Parsing trn")
    @time (h,x,y)=KUparser.oparse(trn, feats, ncpu)
    @show evalheads(h,trn)
else
    msg("Parsing dev")
    @time (h,x,y)=KUparser.oparse(dev, feats, ncpu)
    @show evalheads(h,dev)
end

msg("Setting up net")
net=KUnet.newnet(KUnet.relu, 1326, 20000, 3; learningRate=2f-2, adagrad=1f-8, dropout=7f-1)
KUnet.setparam!(net[1]; dropout=2f-1)
net[end].f=KUnet.logp
@show net

nexttest = 1
for epoch=1:256
    msg("epoch=$epoch")
    @time KUnet.train(net, x, y; batch=128, loss=KUnet.logploss)
    if epoch == nexttest
        @everywhere gc()
        msg("KUparser.gparse(trn, net, feats, nbatch, ncpu)")
        @time (htrn,) = KUparser.gparse(trn, net, feats, nbatch, ncpu)
        e1 = evalheads(htrn,trn)
        msg("KUparser.gparse(dev, net, feats, nbatch, ncpu)")
        @time (hdev,) = KUparser.gparse(dev, net, feats, nbatch, ncpu)
        e2 = evalheads(hdev,dev)
        msg("KUparser.gparse(tst, net, feats, nbatch, ncpu)")
        @time (htst,) = KUparser.gparse(tst, net, feats, nbatch, ncpu)
        e3 = evalheads(htst,tst)
        println("$epoch\t$e1\t$e2\t$e3")
        nexttest *= 2
    end
end

msg("done")