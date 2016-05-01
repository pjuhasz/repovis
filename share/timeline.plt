
set xdata time
set format x "%Y/%m/%d"

set border 1
set autoscale
set xtics
unset x2tics
set xtics nomirror out
set ytics
set y2tics
set xdata time
set format x "%Y/%m/%d"  
set timefmt "%s"
set title "Timeline of commits and committers"

set sty fill solid noborder


plot \
	for [uid=1:words(counts)] 'revs.dat' u 4:(uid):4:(maxdate):(uid-0.5):(uid+0.5):(boxrgb(uid, $5, rev)) w boxxy lc rgb var notit, \
	'revs.dat' u 4:1:(0):(0.2):ytic(2):y2tic(word(counts,int(column(1)))) w vec lc rgb 'black' nohead notit, \
	'revs.dat' u ($5==rev?$4:1/0):(0.5):(0):(words(hues)) w vec lc rgb 'red' nohead notit
