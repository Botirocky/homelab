#pragma once

const char WEB_OLDAL[] PROGMEM = R"HTMLOLDAL(<!doctype html>
<html lang="hu">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ébresztő</title>
<style>
:root{--hat:#f4f5f7;--lap:#fff;--szoveg:#1c1f24;--halvany:#6b7280;--vonal:#e3e5e8;--jo:#15803d;--rossz:#b91c1c;--kek:#1d4ed8}
@media (prefers-color-scheme:dark){:root{--hat:#111316;--lap:#1a1d21;--szoveg:#e7e9ec;--halvany:#9aa1ab;--vonal:#2a2e34;--jo:#4ade80;--rossz:#f87171;--kek:#60a5fa}}
*{box-sizing:border-box}
body{margin:0;background:var(--hat);color:var(--szoveg);font:15px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:560px;margin:0 auto;padding:20px 16px 40px}
h1{font-size:18px;margin:0 0 4px}
.al{color:var(--halvany);font-size:13px;margin-bottom:16px}
.gep{background:var(--lap);border:1px solid var(--vonal);border-radius:12px;padding:14px 16px;margin-bottom:10px;display:flex;align-items:center;gap:12px}
.pont{width:10px;height:10px;border-radius:50%;border:2px solid var(--halvany);flex:none}
.pont.fut{background:var(--jo);border-color:var(--jo)}
.nev{flex:1;min-width:0}
.nev b{display:block}
.nev small{color:var(--halvany)}
.gombok{display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end}
button{font:inherit;padding:7px 12px;border-radius:8px;border:1px solid var(--vonal);background:var(--lap);color:var(--szoveg);cursor:pointer}
button.fo{border-color:var(--kek);color:var(--kek)}
button.veszely{border-color:var(--rossz);color:var(--rossz)}
button:disabled{opacity:.4;cursor:default}
#sav{border-radius:12px;padding:12px 16px;margin-bottom:12px;background:var(--lap);border:1px solid var(--vonal)}
#sav:empty{display:none}
.kartya{background:var(--lap);border:1px solid var(--vonal);border-radius:12px;padding:14px 16px;margin-top:18px}
.fej{display:flex;align-items:center;justify-content:space-between;gap:12px}
.fej b{font-size:15px}
.kapcs{position:relative;width:44px;height:26px;flex:none}
.kapcs input{opacity:0;width:0;height:0}
.kapcs span{position:absolute;inset:0;border-radius:13px;background:var(--vonal);transition:.2s;cursor:pointer}
.kapcs span:before{content:"";position:absolute;width:20px;height:20px;left:3px;top:3px;border-radius:50%;background:#fff;transition:.2s}
.kapcs input:checked+span{background:var(--jo)}
.kapcs input:checked+span:before{transform:translateX(18px)}
.kapcs input:focus-visible+span{outline:2px solid var(--kek);outline-offset:2px}
.idok{display:flex;gap:12px;flex-wrap:wrap;margin:12px 0 8px}
.idok label{display:flex;flex-direction:column;gap:4px;font-size:13px;color:var(--halvany)}
input[type=time]{font:inherit;padding:6px 8px;border-radius:8px;border:1px solid var(--vonal);background:var(--hat);color:var(--szoveg)}
#ejAll{display:block;color:var(--halvany);font-size:13px;margin:4px 0 10px}
</style>
</head>
<body>
<main>
<h1>Ébresztő</h1>
<div class="al" id="al">betöltés…</div>
<div id="sav"></div>
<div id="lista"></div>
<section class="kartya">
<div class="fej"><b>Pi éjszakai leállás</b><label class="kapcs" title="be / ki"><input type="checkbox" id="ejBe" onchange="ejMent(true)"><span></span></label></div>
<div class="idok"><label>Leállás<input type="time" id="ejLe" value="22:00"></label><label>Ébresztés<input type="time" id="ejEb" value="08:00"></label></div>
<small id="ejAll"></small>
<div class="gombok" style="justify-content:flex-start"><button class="fo" onclick="ejMent(false)">Időpontok mentése</button><button onclick="piProba()">Pi ébresztés próba</button></div>
</section>
</main>
<script>
const $=id=>document.getElementById(id);
const esc=s=>String(s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
let foglalt=false;
function kulcs(){let k="";try{k=localStorage.getItem("kulcs")||""}catch(e){}if(!k){k=prompt("Az ébresztő kulcsa:")||"";try{if(k)localStorage.setItem("kulcs",k)}catch(e){}}return k}
async function muvelet(gep,mit,kerdes){
  if(kerdes&&!confirm(kerdes))return;
  const k=kulcs();if(!k)return;
  const v=await fetch("/api/muvelet",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:`gep=${gep}&mit=${mit}&kulcs=${encodeURIComponent(k)}`});
  if(v.status==403){try{localStorage.removeItem("kulcs")}catch(e){}}
  $("sav").textContent=await v.text();frissit();
}
let ejBetoltve=false;
async function kuld(ut,test){
  const k=kulcs();if(!k)return null;
  const v=await fetch(ut,{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:test+"&kulcs="+encodeURIComponent(k)});
  if(v.status==403){try{localStorage.removeItem("kulcs")}catch(e){}}
  $("sav").textContent=await v.text();return v.ok;
}
async function ejMent(csakKapcs){
  const be=$("ejBe").checked?1:0;
  let test="be="+be;
  if(!csakKapcs)test+="&leall="+encodeURIComponent($("ejLe").value)+"&ebreszt="+encodeURIComponent($("ejEb").value);
  const jo=await kuld("/api/ejszaka",test);
  if(!jo)ejBetoltve=false;
  frissit();
}
async function piProba(){
  if(!confirm("Rövid impulzust küld a Pi GPIO3-ára. Ha a Pi le van állítva, elindul; ha fut, nem történik semmi."))return;
  await kuld("/api/pi-ebreszt","x=1");
}
function ejRajzol(e,piOk){
  if(!ejBetoltve){$("ejBe").checked=e.be;$("ejLe").value=e.leall;$("ejEb").value=e.ebreszt;ejBetoltve=true}
  let t;
  if(!e.be)t="Kikapcsolva – a Pi folyamatosan fut.";
  else if(!piOk)t=`A Pi most nem érhető el (alszik?). Ébresztés: ${e.ebreszt}.`;
  else if(e.pi_fut)t="A Pi leállásra vár, mert még fut: "+(e.pi_ok||"…");
  else if(e.pi_allapot=="feladva")t=`Legutóbb nem állt le: a várakozási idő alatt sem szabadult fel. Ma ${e.leall}-kor újra próbálja.`;
  else t=`Leállás ${e.leall}-kor (megvárja a futó feladatokat), ébresztés ${e.ebreszt}-kor.`;
  $("ejAll").textContent=t;
}
async function frissit(){
  let d;
  try{d=await (await fetch("/api/allapot")).json()}catch(e){$("al").textContent="az ébresztő nem válaszol";return}
  foglalt=d.folyamat.fut;
  ejRajzol(d.ejszaka,d.pi);
  $("al").textContent=(d.pi?"":"a Pi nem érhető el · ")+"WiFi "+d.rssi+" dBm";
  if(foglalt)$("sav").textContent=`${d.gepek[d.folyamat.gep].nev}: ${d.folyamat.muvelet} folyamatban… ${d.folyamat.mp} mp`;
  else if(d.folyamat.utolso)$("sav").innerHTML=`<b style="color:var(--${d.folyamat.jo?"jo":"rossz"})">${esc(d.folyamat.utolso)}</b>`;
  $("lista").innerHTML=d.gepek.map((g,i)=>{
    const fut=g.allapot=="fut",dis=foglalt?"disabled":"";
    let gombok="";
    if(g.tipus=="wol")gombok=`<button class="fo" ${dis||(fut?"disabled":"")} onclick="muvelet(${i},'ebreszt')">Ébresztés</button>`;
    else if(fut)gombok=`<button ${dis} onclick="muvelet(${i},'leallit','Leállítod: ${esc(g.nev)}?')">Leállítás</button><button class="veszely" ${dis} onclick="muvelet(${i},'kenyszer','Kényszer-leállítás: ${esc(g.nev)}? A mentetlen adatok elvesznek.')">Kényszer</button>`;
    else gombok=`<button class="fo" ${dis} onclick="muvelet(${i},'indit')">Indítás</button>`;
    const allapot=g.allapot=="fut"?"fut":g.allapot=="all"?(g.tipus=="wol"?"alszik / kikapcsolva":"leállítva"):"ismeretlen";
    return `<div class="gep"><span class="pont ${fut?"fut":""}"></span><div class="nev"><b>${esc(g.nev)}</b><small>${g.tipus=="wol"?"Wake-on-LAN":g.tipus+" VM"} · ${allapot}</small></div><div class="gombok">${gombok}</div></div>`;
  }).join("");
}
frissit();setInterval(()=>frissit(),foglalt?1500:4000);setInterval(()=>{if(foglalt)frissit()},1500);
</script>
</body>
</html>
)HTMLOLDAL";
