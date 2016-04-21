set termoption noenhanced

set size ratio -1
set sty fill solid noborder

unset border
unset xtics
unset ytics

fn = 'calgobackend.txt' ##

curves = "PeanoCurve \
	WunderlichSerpentine \
	HilbertCurve \
	HilbertSpiral \
	ZOrderCurve \
	WunderlichMeander \
	BetaOmega \
	AR2W2Curve \
	KochelCurve \
	DekkingCurve \
	DekkingCentres \
	CincoCurve"

max_cid = words(curves)
cst = 7
fcst = 2
cid = 0

bind j 'cid = cid > 0       ? cid - 1 : cid; eval plotcmd'
bind k 'cid = cid < max_cid ? cid + 1 : cid; eval plotcmd'

#userid_cmds = \
#	"set title 'User mode with '.word(curves, cid+1);" .\
#	"plot fn u cst+2*cid:cst+1+2*cid:(0.5):(0.5):2 index 0 w boxxy lc var notit;"
#bind U 'plotcmd = userid_cmds; eval plotcmd'

blame_cmds  = \
	"set title 'Blame mode with '.word(curves, cid+1);" .\
	"plot fn u cst+2*cid:cst+1+2*cid:(0.5):(0.5):6 index 0  w boxxy lc rgb var notit;"
bind B 'plotcmd = blame_cmds; eval plotcmd'

file_cmds  = \
	"set title 'File mode with '.word(curves, cid+1);" .\
	"plot fn u cst+2*cid:cst+1+2*cid:(0.5):(0.5):5 index 0  w boxxy lc rgb var notit," .\
	"fn u fcst+2*cid:fcst+1+2*cid:1 index 1 w labels center notit"
bind F 'plotcmd = file_cmds; eval plotcmd'

eval file_cmds
