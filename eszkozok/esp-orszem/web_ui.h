#pragma once

const char WEB_OLDAL[] PROGMEM = R"HTMLOLDAL(<!doctype html>
<html lang="hu">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>picloud őrszem</title>
<style>
:root{--hat:#f4f5f7;--lap:#fff;--szoveg:#1c1f24;--halvany:#6b7280;--vonal:#e3e5e8;--jo:#15803d;--figy:#b45309;--rossz:#b91c1c;--jo-h:#dcfce7;--figy-h:#fef3c7;--rossz-h:#fee2e2}
@media (prefers-color-scheme:dark){:root{--hat:#111316;--lap:#1a1d21;--szoveg:#e7e9ec;--halvany:#9aa1ab;--vonal:#2a2e34;--jo:#4ade80;--figy:#fbbf24;--rossz:#f87171;--jo-h:#12301d;--figy-h:#3a2c0c;--rossz-h:#3d1414}}
*{box-sizing:border-box}
body{margin:0;background:var(--hat);color:var(--szoveg);font:15px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:760px;margin:0 auto;padding:20px 16px 40px}
h1{font-size:18px;margin:0 0 16px;display:flex;justify-content:space-between;align-items:baseline}
h1 small{font-weight:400;color:var(--halvany);font-size:13px}
.fo{border-radius:12px;padding:18px 20px;margin-bottom:16px;border:1px solid var(--vonal)}
.fo b{font-size:22px;display:block}
.fo span{color:var(--halvany)}
.jo{background:var(--jo-h)}.jo b{color:var(--jo)}
.figy{background:var(--figy-h)}.figy b{color:var(--figy)}
.rossz{background:var(--rossz-h)}.rossz b{color:var(--rossz)}
.racs{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin-bottom:16px}
.lap{background:var(--lap);border:1px solid var(--vonal);border-radius:12px;padding:14px 16px}
.lap h2{font-size:12px;text-transform:uppercase;letter-spacing:.06em;color:var(--halvany);margin:0 0 8px;font-weight:600}
.sor{display:flex;justify-content:space-between;gap:12px;padding:3px 0}
.sor span:last-child{text-align:right}
.sor span:first-child{color:var(--halvany)}
.nagy{font-size:28px;font-weight:600}
ul{list-style:none;margin:0;padding:0}
li{padding:6px 0;border-top:1px solid var(--vonal);display:flex;gap:12px}
li:first-child{border-top:0}
li time{color:var(--halvany);white-space:nowrap;font-variant-numeric:tabular-nums;min-width:92px}
button{font:inherit;padding:8px 14px;border-radius:8px;border:1px solid var(--vonal);background:var(--lap);color:var(--szoveg);cursor:pointer}
button.veszely{border-color:var(--rossz);color:var(--rossz)}
button:disabled{opacity:.45;cursor:default}
.gombok{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
#uzenet{color:var(--halvany);margin-top:8px;min-height:1.4em}
</style>
</head>
<body>
<main>
<h1>picloud őrszem <small id="frissitve"></small></h1>
<div id="fo" class="fo"><b>Betöltés…</b><span></span></div>
<div class="racs">
  <section class="lap"><h2 id="pinev">picloud</h2><div id="pi"></div></section>
  <section class="lap" id="racklap" hidden><h2>A Pi körül</h2><div class="nagy" id="rackho"></div><div id="rack"></div></section>
  <section class="lap"><h2>Kiesések</h2><div id="kieses"></div></section>
  <section class="lap"><h2>Őrszem</h2><div id="orszem"></div></section>
</div>
<section class="lap" style="margin-bottom:16px">
  <h2>Műveletek</h2>
  <div class="gombok">
    <button id="teszt">Teszt-értesítés</button>
    <button id="nemit" class="veszely">Riasztó némítása</button>
  </div>
  <div id="uzenet"></div>
</section>
<section class="lap"><h2>Események</h2><ul id="esemenyek"></ul></section>
</main>
<script>
const $=id=>document.getElementById(id);
const esc=s=>String(s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const sor=(k,v)=>`<div class="sor"><span>${esc(k)}</span><span>${esc(v)}</span></div>`;
function hossz(mp){if(mp<60)return mp+" mp";if(mp<3600)return Math.floor(mp/60)+" perc";if(mp<86400)return Math.floor(mp/3600)+" óra "+Math.floor(mp%3600/60)+" perc";return Math.floor(mp/86400)+" nap "+Math.floor(mp%86400/3600)+" óra"}
function datum(t){if(!t)return "–";const d=new Date(t*1000);return d.toLocaleString("hu-HU",{month:"2-digit",day:"2-digit",hour:"2-digit",minute:"2-digit"})}
async function frissit(){
  let d;
  try{d=await (await fetch("/api/allapot")).json()}catch(e){$("frissitve").textContent="az őrszem nem válaszol";return}
  const osztaly=d.kieses.aktiv||d.allapot=="nem_valaszol"?"rossz":d.allapot=="rendben"?"jo":"figy";
  $("fo").className="fo "+osztaly;
  const cim=d.kieses.aktiv?"A picloud leállt":d.allapot=="rendben"?"A picloud rendben":"picloud: "+d.szoveg;
  $("fo").innerHTML=`<b>${esc(cim)}</b><span>${d.kieses.aktiv?hossz(d.kieses.tart_mp)+" óta nem válaszol":"ebben az állapotban "+hossz(d.ota_mp)+" óta"}</span>`;
  $("pinev").textContent=d.pi.gep;
  const p=d.pi;
  $("pi").innerHTML=p.van?sor("CPU",p.cpu+" %")+sor("Hőmérséklet",p.ho!=null?p.ho.toFixed(1)+" °C":"–")+sor("Memória",p.ram+" %")+sor("Legtelibb lemez",p.lemez+" %")+sor("Konténerek",p.kont_fut+" / "+p.kont_ossz)+sor("Üzemidő",hossz(p.uptime))+sor("Utolsó adat",datum(p.ido)):"<span style='color:var(--halvany)'>még nem jött adat</span>";
  if(d.rack){$("racklap").hidden=false;$("rackho").textContent=d.rack.ho.toFixed(1)+" °C";$("rack").innerHTML=sor("Páratartalom",d.rack.para+" %")+sor("Légnyomás",d.rack.nyomas+" hPa")}
  const k=d.kieses,o=d.orszem;
  $("kieses").innerHTML=sor("Összesen",k.db)+sor("Utolsó",k.utolso?datum(k.utolso):"–")+sor("Utolsó hossza",k.utolso_mp?hossz(k.utolso_mp):"–");
  $("orszem").innerHTML=sor("IP",o.ip)+sor("WiFi-jel",o.rssi+" dBm")+sor("Fut",hossz(o.uptime))+sor("Értesítés",[o.ntfy&&"ntfy",o.discord&&"Discord"].filter(Boolean).join(", ")||"nincs beállítva")+sor("Kijelző / szenzor",(o.oled?"OLED":"–")+" / "+(o.bme?"BME280":"–"))+(o.fuggo?sor("Küldésre vár",o.fuggo+" értesítés"):"");
  $("esemenyek").innerHTML=d.esemenyek.map(e=>`<li><time>${esc(e.ido)}</time><span>${esc(e.szoveg)}</span></li>`).join("")||"<li>nincs még esemény</li>";
  $("nemit").disabled=!k.aktiv||k.nemitva;$("nemit").textContent=k.nemitva?"Riasztó némítva":"Riasztó némítása";
  $("teszt").disabled=!(o.ntfy||o.discord);
  $("frissitve").textContent="frissítve "+new Date().toLocaleTimeString("hu-HU");
}
async function kuld(url,body){
  const v=await fetch(url,{method:"POST",body,headers:body?{"Content-Type":"application/x-www-form-urlencoded"}:{}});
  $("uzenet").textContent=await v.text();frissit();
}
$("teszt").onclick=()=>kuld("/api/teszt");
$("nemit").onclick=()=>kuld("/api/nemit");
frissit();setInterval(frissit,5000);
</script>
</body>
</html>
)HTMLOLDAL";
