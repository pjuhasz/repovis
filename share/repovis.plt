load 'params.inc'

if (!exists("rev")) rev = maxrev

strrev(rev) = sprintf("%05d", rev)
fn(rev, mode) = '' . strrev(rev) . '_' . mode . '.dat'

boxrgb(uid, rev, cur_rev) = hsv2rgb(word(hues, uid)/360, 0.03+0.93*(rev>cur_rev?1:rev/cur_rev), 1)

# key bindings for interactive mode
bind F 'mode = "f"; load "matrix.plt"'  
bind B 'mode = "b"; load "matrix.plt"'  
bind T 'load "timeline.plt"'

bind j 'rev = rev > 0      ? rev-1 : rev; load "matrix.plt"'
bind k 'rev = rev < maxrev ? rev+1 : rev; load "matrix.plt"'

mode = 'f'
load "matrix.plt"


