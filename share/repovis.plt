if (!exists("rev")) rev = "00001"

fn(rev, mode) = '' . rev . '_' . mode . '.dat'

set termoption noenhanced

set size ratio -1
set sty fill solid noborder

unset border
unset xtics
unset ytics

plotcmd = \
	"set title (mode eq 'b'?'Blame':'File').' map for revision '.rev;" .\
	"plot fn(rev, mode) binary filetype=avs flipy endian=little w rgbalpha notit," .\
	"fn(rev, 'c') u 1:2:3:4 w vec nohead lc rgb 'gray' lw 2 notit," .\
	"fn(rev, 'l') u 2:3:1 w labels center notit"

bind F 'mode = "f"; eval plotcmd'  
bind B 'mode = "b"; eval plotcmd'  

# FIXME from real repo logs
bind j '_rev = int(rev); _rev = _rev > 0     ? _rev-1 : _rev; rev = sprintf("%05d", _rev); eval plotcmd'
bind k '_rev = int(rev); _rev = _rev < 10000 ? _rev+1 : _rev; rev = sprintf("%05d", _rev); eval plotcmd'

mode = 'f'
eval plotcmd
