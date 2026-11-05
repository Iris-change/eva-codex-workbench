export const clamp=x=>Math.max(0,Math.min(1,x));
// Quintic S curve: zero velocity and acceleration at both endpoints.
export function sCurve(x){x=clamp(x);return x*x*x*(x*(x*6-15)+10)}
export const stage=(time,start,end)=>sCurve((time-start)/(end-start));
export function loopTime(time,period=1,offset=0){const phase=time/period+offset,lap=Math.floor(phase);return lap+sCurve(phase-lap)}
export function pingPong(time,legSeconds=1,offset=0){const phase=((time/legSeconds+offset)%2+2)%2;return sCurve(phase<=1?phase:2-phase)}
export const breathe=(time,period=4,offset=0)=>(1-Math.cos(loopTime(time,period,offset)*Math.PI*2))/2;
export function curvePoint(p,a,b,c,d){const q=1-p;return {x:q*q*q*a.x+3*q*q*p*b.x+3*q*p*p*c.x+p*p*p*d.x,y:q*q*q*a.y+3*q*q*p*b.y+3*q*p*p*c.y+p*p*p*d.y}}
export function scanPosition(time,height,legSeconds){return -72+pingPong(time,legSeconds)*(height+144)}
