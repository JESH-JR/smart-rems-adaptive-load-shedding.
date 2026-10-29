import json,sys,pandas as pd,numpy as np, scipy.io as sio
from scipy.interpolate import PchipInterpolator
raw,old_csv,out=sys.argv[1:4]
CLEAR,CLOUDY='2025-05-09','2025-05-16'
d=json.load(open(raw))
H=pd.DataFrame(d['hourly']); H.index=pd.to_datetime(H.index,format='%Y%m%d%H')
t=np.arange(1440)/60.0
def minute_profile(day):
    h=H.loc[day]; G=h.ALLSKY_SFC_SW_DWN.values.astype(float); T=h.T2M.values.astype(float)
    tc=np.arange(24)+0.5                       # hourly mean placed mid-hour
    # irradiance: pchip through hour midpoints, anchored to 0 at the edges of the daylight window
    lit=np.where(G>0)[0]; a,b=lit[0],lit[-1]
    xs=np.r_[a, tc[a:b+1], b+1.0]; ys=np.r_[0, G[a:b+1], 0]
    g=np.zeros_like(t); m=(t>=a)&(t<=b+1); g[m]=PchipInterpolator(xs,ys)(t[m]); g=np.clip(g,0,None)
    # keep each hour's energy equal to NASA's hourly mean
    g*=G.sum()/(g.sum()/60)                    # keep NASA daily energy exactly (smooth curve, no hour steps)
    hm=np.array([g[(t>=k)&(t<k+1)].mean() for k in range(24)])
    print(day,'max hourly-mean deviation from NASA: %.1f W/m2'%np.abs(hm-G).max())
    Tm=np.interp(t,np.r_[tc-24,tc,tc+24],np.r_[T,T,T])   # periodic smooth temperature
    return g,Tm,G,T
gC,TC,GC_h,TC_h=minute_profile(CLEAR); gK,TK,GK_h,TK_h=minute_profile(CLOUDY)
noct=lambda G,T: T+(45-20)/800*G
TcC,TcK=noct(gC,TC),noct(gK,TK)
P=lambda G,Tc: 6.84432*G*(1-0.004*(Tc-25))          # same column definition as the original file
df=pd.DataFrame({'time_h':t,'G_clear_Wm2':gC,'G_cloudy_Wm2':gK,'T_amb_C':TC,'Tcell_clear_C':TcC,
                 'Tcell_cloudy_C':TcK,'P_PV_clear_W':P(gC,TcC),'P_PV_cloudy_W':P(gK,TcK),'T_amb_cloudy_C':TK})
df.to_csv(out+'/pv_daily_profile.csv',index=False)
col=lambda x: np.asarray(x,float).reshape(-1,1)
sio.savemat(out+'/pv_daily_profile.mat',{'t':col(t),'G_clear':col(gC),'G_cloudy':col(gK),'T_amb':col(TC),
   'Tc_clear':col(TcC),'Tc_cloudy':col(TcK),'P_clear':col(P(gC,TcC)),'P_cloudy':col(P(gK,TcK)),'T_amb_cloudy':col(TK)})
# raw hourly source rows for traceability
src=pd.concat({'clear '+CLEAR:H.loc[CLEAR],'cloudy '+CLOUDY:H.loc[CLOUDY]})
src.to_csv(out+'/nasa_power_hourly_source.csv')
# stats
old=pd.read_csv(old_csv)
E=lambda g: g.sum()/60/1000
def unitE(G,Tc): return (19.2*G/1000*(1-0.004*(Tc-25))).sum()/60   # kWh, 19.2 kW unit, relative only
r=unitE(gC,TcC)/unitE(old.G_clear_Wm2,old.Tcell_clear_C)
print(f'clear  {CLEAR}: {E(gC):.2f} kWh/m2 (NASA hourly {GC_h.sum()/1000:.2f}), peak {gC.max():.0f} W/m2, Tamb {TC.min():.1f}-{TC.max():.1f}, Tcell max {TcC.max():.1f}')
print(f'cloudy {CLOUDY}: {E(gK):.2f} kWh/m2 (NASA hourly {GK_h.sum()/1000:.2f}), peak {gK.max():.0f}, Tamb {TK.min():.1f}-{TK.max():.1f}')
print(f'old synthetic clear {E(old.G_clear_Wm2):.2f} kWh/m2, cloudy {E(old.G_cloudy_Wm2):.2f}')
print(f'PV energy ratio new/old clear (temp-corrected) {r:.3f} -> est. per unit {101.6*r:.1f} kWh, two units {203*r:.0f} kWh, coverage {203*r/211.6:.2f}')
rk=unitE(gK,TcK)/unitE(old.G_clear_Wm2,old.Tcell_clear_C); print(f'cloudy est two units {203*rk:.0f} kWh, coverage {203*rk/211.6:.2f}')
print('sunrise/sunset clear', t[np.argmax(gC>0)], t[1439-np.argmax(gC[::-1]>0)])
