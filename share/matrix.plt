set termoption noenhanced

set size ratio -1
set sty fill solid noborder

unset xdata
unset border
unset xtics
unset ytics

set title (mode eq 'b'?'Blame':'File').' map for revision '.rev

plot \
	fn(rev, mode) binary filetype=avs flipy endian=little w rgbalpha notit, \
	fn(rev, 'c') u 1:2:3:4 w vec nohead lc rgb 'gray' lw 2 notit, \
	fn(rev, 'l') u 2:3:1 w labels center notit
