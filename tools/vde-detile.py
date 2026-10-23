import numpy as np
def gob_index(w,h):
    y,x=np.mgrid[0:h,0:w]
    return ((y//8)*(w//64)+x//64)*512 + ((x%64)//32)*256 + ((y%8)//2)*64 + ((x%32)//16)*32 + (y%2)*16 + (x%16)
def detile_frame(buf,W,H):
    # planes as delivered (W*H, W*H/4, W*H/4 bytes); rows past a plane's end (GOB padding) read as 0
    out=[]; off=0
    for (w,h) in ((W,H),(W//2,H//2),(W//2,H//2)):
        n=w*h; plane=buf[off:off+n]; idx=gob_index(w,h)
        safe=np.where(idx<n, idx, 0); o=plane[safe]; o[idx>=n]=0; out.append(o); off+=n
    return out
