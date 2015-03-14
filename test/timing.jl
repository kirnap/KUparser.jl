isdefined(:g0) || @time g0=KUparser.gparse(dev,gnet,feats)
isdefined(:g1) || @time g1=KUparser.gparse(dev,gnet,feats,1700)
@show isequal(g1,g0)
isdefined(:g2) || @time g2=KUparser.gparse(dev,gnet,feats,1700,20)
@show isequal(g2,g0)
isdefined(:g3) || @time g3=KUparser.gparse(dev,gnet,feats,100)
@show isequal(g3,g0)
isdefined(:g4) || @time g4=KUparser.gparse(dev,gnet,feats,100,20)
@show isequal(g4,g0)

isdefined(:b0) || @time b0=KUparser.bparse(dev,gnet,feats,1)
@show isequal(b0,g0)
isdefined(:b1) || @time b1=KUparser.bparse(dev,gnet,feats,1,1700)
@show isequal(b1,g0)
isdefined(:b2) || @time b2=KUparser.bparse(dev,gnet,feats,1,1700,20)
@show isequal(b2,g0)
isdefined(:b3) || @time b3=KUparser.bparse(dev,gnet,feats,1,100)
@show isequal(b3,g0)
isdefined(:b4) || @time b4=KUparser.bparse(dev,gnet,feats,1,100,20)
@show isequal(b4,g0)

isdefined(:b01) || @time b01=KUparser.bparse(dev[1:100],gnet,feats,10)
@show isequal(b01,g0[1:100])
isdefined(:b11) || @time b11=KUparser.bparse(dev[1:100],gnet,feats,10,100)
@show isequal(b11,b01)
isdefined(:b21) || @time b21=KUparser.bparse(dev[1:100],gnet,feats,10,100,20)
@show isequal(b21,b01)
isdefined(:b31) || @time b31=KUparser.bparse(dev[1:100],gnet,feats,10,10)
@show isequal(b31,b01)
isdefined(:b41) || @time b41=KUparser.bparse(dev[1:100],gnet,feats,10,10,20)
@show isequal(b41,b01)

isdefined(:b02) || @time b02=KUparser.bparse(dev[1:100],gnet,feats,100)
@show isequal(b02,g0[1:100])
@show isequal(b02,b01)
isdefined(:b12) || @time b12=KUparser.bparse(dev[1:100],gnet,feats,100,100)
@show isequal(b12,b02)
isdefined(:b22) || @time b22=KUparser.bparse(dev[1:100],gnet,feats,100,100,20)
@show isequal(b22,b02)
isdefined(:b32) || @time b32=KUparser.bparse(dev[1:100],gnet,feats,100,10)
@show isequal(b32,b02)
isdefined(:b42) || @time b42=KUparser.bparse(dev[1:100],gnet,feats,100,10,20)
@show isequal(b42,b02)
