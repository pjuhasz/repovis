if (!exists("rev")) rev = "1"

fn(rev, mode) = rev . '_' . mode . '.dat'

set termoption noenhanced

set size ratio -1
set sty fill solid noborder

unset border
unset xtics
unset ytics

plotcmd = \
	"plot fn(rev, mode) binary filetype=avs flipy endian=little w rgbimage notit," .\
	"fn(rev, 'c') u 1:2:3:4 w vec nohead lc rgb 'gray' lw 2 notit," .\
	"fn(rev, 'l') u 2:3:1 w labels center notit"

bind F 'mode = "f"; eval plotcmd'  
bind B 'mode = "b"; eval plotcmd'  

mode = 'f'
eval plotcmd
