
set xdata time
set format x "%Y/%m/%d"

set autoscale
set xtics
set ytics
set y2tics
set xdata time
set format x "%Y/%m/%d"  
set timefmt "%s"


set sty fill solid noborder


plot \
	for [uid=1:4] 'revs.dat' u 4:(uid):4:(maxdate):(uid-0.5):(uid+0.5):(boxrgb(uid, $5, rev)) w boxxy lc rgb var notit, \
	'revs.dat' u 4:1:(0):(0.2):ytic(2)::y2tic(word(counts,int(column(1)))) w vec lc rgb 'black' nohead notit, \
	'revs.dat' u ($5==rev?$4:1/0):(0.5):(0):(words(hues)) w vec lc rgb 'red' nohead notit
