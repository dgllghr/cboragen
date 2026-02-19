var HG=new TextEncoder,PG=new TextDecoder,B=new Uint8Array(256),U=new DataView(B.buffer),$=0;function P(G){if($+G<=B.length)return;let J=B.length;while(J<$+G)J*=2;let O=new Uint8Array(J);O.set(B),B=O,U=new DataView(B.buffer)}function x(G){P(1),B[$++]=G}function EG(G){P(2),U.setUint16($,G),$+=2}function WG(G){P(4),U.setUint32($,G),$+=4}function XG(G){P(8),U.setBigUint64($,G),$+=8}function k(G,J){let O=typeof J==="bigint"?J:BigInt(J);if(O<=23n)x(G|Number(O));else if(O<=0xffn)x(G|24),x(Number(O));else if(O<=0xffffn)x(G|25),EG(Number(O));else if(O<=0xffffffffn)x(G|26),WG(Number(O));else x(G|27),XG(O)}function YG(G){x(G?245:244)}function TG(G){x(24),x(G)}function ZG(G){x(26),WG(G)}function A(G){x(27),XG(G)}function $G(G){k(0,G)}function T(G){x(251),P(8),U.setFloat64($,G),$+=8}function R(G){let J=HG.encode(G);k(96,J.length),P(J.length),B.set(J,$),$+=J.length}function fG(G){k(64,G.length),P(G.length),B.set(G,$),$+=G.length}function Q(G){k(128,G)}function AG(G){k(192,G)}function M(){$=0}function j(){let G=B.slice(0,$);return $=0,G}var w,g,Y;function h(G){w=G,g=new DataView(G.buffer,G.byteOffset,G.byteLength),Y=0}function I(){return w[Y++]}function a(){let G=g.getUint16(Y);return Y+=2,G}function m(){let G=g.getUint32(Y);return Y+=4,G}function l(){let G=g.getBigUint64(Y);return Y+=8,G}function qG(){let G=I();if(G===245)return!0;if(G===244)return!1;throw Error("expected bool")}function SG(){if(I()!==24)throw Error("expected u8");return I()}function xG(){if(I()!==26)throw Error("expected u32");return m()}function S(){if(I()!==27)throw Error("expected u64");return l()}function _(G){let J=I(),O=J>>5;if(O!==G)throw Error("unexpected major type "+O);let V=J&31;if(V<=23)return V;if(V===24)return I();if(V===25)return a();if(V===26)return m();if(V===27)return Number(l());throw Error("unsupported additional info "+V)}function QG(){let J=I()&31;if(J<=23)return BigInt(J);if(J===24)return BigInt(I());if(J===25)return BigInt(a());if(J===26)return BigInt(m());if(J===27)return l();throw Error("expected uvarint")}function f(){if(I()!==251)throw Error("expected f64");let G=g.getFloat64(Y);return Y+=8,G}function y(){let G=_(3),J=PG.decode(w.subarray(Y,Y+G));return Y+=G,J}function UG(){let G=_(2),J=w.slice(Y,Y+G);return Y+=G,J}function F(){return _(4)}function N(){let G=I(),J=G>>5,O=G&31;if(J===7){if(O<=23)return;if(O===24){Y+=1;return}if(O===25){Y+=2;return}if(O===26){Y+=4;return}if(O===27){Y+=8;return}return}let V;if(O<=23)V=O;else if(O===24)V=I();else if(O===25)V=a();else if(O===26)V=m();else if(O===27)V=Number(l());else if(O===31){while(w[Y]!==255)N();Y++;return}else throw Error("unsupported AI in skip");if(J===0||J===1)return;if(J===2||J===3){Y+=V;return}if(J===4){for(let K=0;K<V;K++)N();return}if(J===5){for(let K=0;K<V*2;K++)N();return}if(J===6){N();return}}function FG(G){Q(3),T(G.x),T(G.y),T(G.z)}function b(G){return M(),FG(G),j()}function n(G){Q(8),A(G.id),R(G.username),R(G.email),TG(G.age),YG(G.active),T(G.score),Q(G.tags.length);for(let J=0;J<G.tags.length;J++)R(G.tags[J]);G.metadata===null?x(0):(AG(1),kG(G.metadata))}function v(G){return M(),n(G),j()}function kG(G){Q(4),A(G.createdAt),A(G.lastLogin),ZG(G.loginCount),MG(G.preferences)}function MG(G){Q(3),jG(G.theme),YG(G.notifications),R(G.language)}function jG(G){$G(BigInt(G))}function wG(G){Q(8),A(G.id),n(G.sender),Q(G.recipients.length);for(let J=0;J<G.recipients.length;J++)n(G.recipients[J]);R(G.subject),R(G.body),Q(G.attachments.length);for(let J=0;J<G.attachments.length;J++)gG(G.attachments[J]);hG(G.priority),A(G.timestamp)}function c(G){return M(),wG(G),j()}function gG(G){Q(4),R(G.name),R(G.mimeType),ZG(G.size),fG(G.data)}function hG(G){$G(BigInt(G))}function pG(G){Q(2),Q(G.points.length);for(let J=0;J<G.points.length;J++)FG(G.points[J]);R(G.name)}function o(G){return M(),pG(G),j()}function uG(G){Q(2),Q(G.values.length);for(let J=0;J<G.values.length;J++)T(G.values[J]);R(G.label)}function s(G){return M(),uG(G),j()}function IG(){let G=F(),J=void 0,O=void 0,V=void 0;if(G>0)J=f();if(G>1)O=f();if(G>2)V=f();for(let K=3;K<G;K++)N();return{x:J,y:O,z:V}}function e(G){return h(G),IG()}function d(){let G=F(),J=void 0,O=void 0,V=void 0,K=void 0,W=void 0,X=void 0,z=void 0,D=null;if(G>0)J=S();if(G>1)O=y();if(G>2)V=y();if(G>3)K=SG();if(G>4)W=qG();if(G>5)X=f();if(G>6)z=(()=>{let q=F(),L=[];for(let C=0;C<q;C++)L.push(y());return L})();if(G>7)D=I()===0?null:mG();for(let q=8;q<G;q++)N();return{id:J,username:O,email:V,age:K,active:W,score:X,tags:z,metadata:D}}function GG(G){return h(G),d()}function mG(){let G=F(),J=void 0,O=void 0,V=void 0,K=void 0;if(G>0)J=S();if(G>1)O=S();if(G>2)V=xG();if(G>3)K=lG();for(let W=4;W<G;W++)N();return{createdAt:J,lastLogin:O,loginCount:V,preferences:K}}function lG(){let G=F(),J=void 0,O=void 0,V=void 0;if(G>0)J=bG();if(G>1)O=qG();if(G>2)V=y();for(let K=3;K<G;K++)N();return{theme:J,notifications:O,language:V}}function bG(){return Number(QG())}function vG(){let G=F(),J=void 0,O=void 0,V=void 0,K=void 0,W=void 0,X=void 0,z=void 0,D=void 0;if(G>0)J=S();if(G>1)O=d();if(G>2)V=(()=>{let q=F(),L=[];for(let C=0;C<q;C++)L.push(d());return L})();if(G>3)K=y();if(G>4)W=y();if(G>5)X=(()=>{let q=F(),L=[];for(let C=0;C<q;C++)L.push(cG());return L})();if(G>6)z=oG();if(G>7)D=S();for(let q=8;q<G;q++)N();return{id:J,sender:O,recipients:V,subject:K,body:W,attachments:X,priority:z,timestamp:D}}function JG(G){return h(G),vG()}function cG(){let G=F(),J=void 0,O=void 0,V=void 0,K=void 0;if(G>0)J=y();if(G>1)O=y();if(G>2)V=xG();if(G>3)K=UG();for(let W=4;W<G;W++)N();return{name:J,mimeType:O,size:V,data:K}}function oG(){return Number(QG())}function sG(){let G=F(),J=void 0,O=void 0;if(G>0)J=(()=>{let V=F(),K=[];for(let W=0;W<V;W++)K.push(IG());return K})();if(G>1)O=y();for(let V=2;V<G;V++)N();return{points:J,name:O}}function KG(G){return h(G),sG()}function tG(){let G=F(),J=void 0,O=void 0;if(G>0)J=(()=>{let V=F(),K=[];for(let W=0;W<V;W++)K.push(f());return K})();if(G>1)O=y();for(let V=2;V<G;V++)N();return{values:J,label:O}}function OG(G){return h(G),tG()}function r(G){return{id:BigInt(G),username:`user_${G}`,email:`user${G}@example.com`,age:25+G%50,active:G%2===0,score:Math.random()*1000,tags:["tag1","tag2","tag3"].slice(0,G%3+1),metadata:G%3===0?null:{createdAt:BigInt(Date.now()-G*86400000),lastLogin:BigInt(Date.now()),loginCount:G*10,preferences:{theme:G%3,notifications:G%2===0,language:"en-US"}}}}function DG(G){let J=r(G),O=G%5+1,V=[];for(let X=0;X<O;X++)V.push(r(G*100+X));let K=G%3,W=[];for(let X=0;X<K;X++)W.push({name:`file_${X}.pdf`,mimeType:"application/pdf",size:1024*(X+1),data:new Uint8Array(100).fill(X)});return{id:BigInt(G),sender:J,recipients:V,subject:`Message subject ${G}`,body:`This is the body of message ${G}. `.repeat(5),attachments:W,priority:G%4,timestamp:BigInt(Date.now())}}function BG(){return{x:Math.random()*1000,y:Math.random()*1000,z:Math.random()*1000}}function NG(G){let J=[];for(let O=0;O<G;O++)J.push(BG());return{points:J,name:`cloud_${G}`}}function zG(G){let J=[];for(let O=0;O<G;O++)J.push(Math.random()*1000);return{values:J,label:`numbers_${G}`}}function H(G,J){if(typeof J==="bigint")return{__bigint:J.toString()};if(J instanceof Uint8Array)return{__uint8array:Array.from(J)};return J}function CG(G,J){if(J&&typeof J==="object"){let O=J;if("__bigint"in O)return BigInt(O.__bigint);if("__uint8array"in O)return new Uint8Array(O.__uint8array)}return J}function Z(G,J,O=500){let V=performance.now()+50,K=0;while(performance.now()<V&&K<100)J(),K++;let W=0,X=performance.now(),z=X+O,D=Math.max(1,Math.floor(K/10))||10;while(performance.now()<z){for(let C=0;C<D;C++)J();W+=D}let q=performance.now()-X,L=W/(q/1000);return{name:G,ops:Math.round(L),avgMs:q/W}}function t(G){if(G>=1e6)return(G/1e6).toFixed(2)+"M";if(G>=1000)return(G/1000).toFixed(2)+"K";return G.toFixed(0)}function LG(G){if(G>=1024)return(G/1024).toFixed(2)+" KB";return G+" B"}var i=document.getElementById("log"),VG=document.getElementById("results"),p=document.getElementById("runBtn"),u=document.getElementById("runQuickBtn");function RG(G){i.textContent=G}function E(G){i.textContent+=`
`+G,i.scrollTop=i.scrollHeight}function iG(G,J){let O="";O+=`<div class="benchmark-section">
    <h3>Correctness Tests</h3>
    <div class="correctness">
      ${G.map((V)=>`<div class="test-result ${V.pass?"pass":"fail"}">${V.name}: ${V.pass?"PASS":"FAIL"}</div>`).join("")}
    </div>
  </div>`;for(let V of J){let K=V.encodeCbor.ops/V.encodeJson.ops,W=V.decodeCbor.ops/V.decodeJson.ops,X=V.jsonSize/V.cborSize,z=K>1?`${K.toFixed(2)}x faster`:`${(1/K).toFixed(2)}x slower`,D=W>1?`${W.toFixed(2)}x faster`:`${(1/W).toFixed(2)}x slower`;O+=`<div class="benchmark-section">
      <h3>${V.name}</h3>
      <p>${V.description}</p>

      <h4>Size Comparison</h4>
      <table>
        <tr class="size-row">
          <td>cboragen</td>
          <td>${LG(V.cborSize)}</td>
          <td rowspan="2" style="color: #4ade80; font-weight: bold;">${X.toFixed(2)}x smaller</td>
        </tr>
        <tr class="size-row">
          <td>JSON</td>
          <td>${LG(V.jsonSize)}</td>
        </tr>
      </table>

      <h4>Encode Performance</h4>
      <table>
        <tr>
          <th>Method</th>
          <th>Ops/sec</th>
          <th>Avg Time</th>
        </tr>
        <tr>
          <td>cboragen</td>
          <td>${t(V.encodeCbor.ops)}</td>
          <td>${V.encodeCbor.avgMs.toFixed(4)} ms</td>
        </tr>
        <tr>
          <td>JSON</td>
          <td>${t(V.encodeJson.ops)}</td>
          <td>${V.encodeJson.avgMs.toFixed(4)} ms</td>
        </tr>
      </table>
      <div class="comparison ${K>1?"faster":"slower"}">
        cboragen is ${z} than JSON
      </div>

      <h4>Decode Performance</h4>
      <table>
        <tr>
          <th>Method</th>
          <th>Ops/sec</th>
          <th>Avg Time</th>
        </tr>
        <tr>
          <td>cboragen</td>
          <td>${t(V.decodeCbor.ops)}</td>
          <td>${V.decodeCbor.avgMs.toFixed(4)} ms</td>
        </tr>
        <tr>
          <td>JSON</td>
          <td>${t(V.decodeJson.ops)}</td>
          <td>${V.decodeJson.avgMs.toFixed(4)} ms</td>
        </tr>
      </table>
      <div class="comparison ${W>1?"faster":"slower"}">
        cboragen is ${D} than JSON
      </div>
    </div>`}VG.innerHTML=O}async function yG(G){let J=G?200:500,O=[],V=[];await new Promise((K)=>setTimeout(K,10)),RG("Running correctness tests..."),await new Promise((K)=>setTimeout(K,10));try{let K={x:1.5,y:2.5,z:3.5},W=b(K),X=e(W);O.push({name:"Point3D",pass:K.x===X.x&&K.y===X.y&&K.z===X.z})}catch(K){O.push({name:"Point3D",pass:!1})}try{let K=r(42),W=v(K),X=GG(W);O.push({name:"User",pass:JSON.stringify(K,H)===JSON.stringify(X,H)})}catch(K){O.push({name:"User",pass:!1})}try{let K=DG(1),W=c(K),X=JG(W);O.push({name:"Message",pass:JSON.stringify(K,H)===JSON.stringify(X,H)})}catch(K){O.push({name:"Message",pass:!1})}try{let K=NG(10),W=o(K),X=KG(W);O.push({name:"PointCloud",pass:JSON.stringify(K)===JSON.stringify(X)})}catch(K){O.push({name:"PointCloud",pass:!1})}try{let K=zG(100),W=s(K),X=OG(W),z=K.label===X.label&&K.values.length===X.values.length&&K.values.every((D,q)=>D===X.values[q]);O.push({name:"Numbers",pass:z})}catch(K){O.push({name:"Numbers",pass:!1})}E("Running Point3D benchmark..."),await new Promise((K)=>setTimeout(K,10));{let K=BG(),W=b(K),X=JSON.stringify(K);V.push({name:"Point3D",description:"Tiny fixed struct (3 f64 values)",cborSize:W.length,jsonSize:X.length,encodeCbor:Z("cboragen",()=>b(K),J),encodeJson:Z("JSON",()=>JSON.stringify(K),J),decodeCbor:Z("cboragen",()=>e(W),J),decodeJson:Z("JSON",()=>JSON.parse(X),J)})}E("Running User benchmark..."),await new Promise((K)=>setTimeout(K,10));{let K=r(42),W=v(K),X=JSON.stringify(K,H);V.push({name:"User",description:"Medium object with optional nested struct",cborSize:W.length,jsonSize:X.length,encodeCbor:Z("cboragen",()=>v(K),J),encodeJson:Z("JSON",()=>JSON.stringify(K,H),J),decodeCbor:Z("cboragen",()=>GG(W),J),decodeJson:Z("JSON",()=>JSON.parse(X,CG),J)})}E("Running Message benchmark..."),await new Promise((K)=>setTimeout(K,10));{let K=DG(1),W=c(K),X=JSON.stringify(K,H);V.push({name:"Message",description:"Complex nested object with arrays of users and attachments",cborSize:W.length,jsonSize:X.length,encodeCbor:Z("cboragen",()=>c(K),J),encodeJson:Z("JSON",()=>JSON.stringify(K,H),J),decodeCbor:Z("cboragen",()=>JG(W),J),decodeJson:Z("JSON",()=>JSON.parse(X,CG),J)})}E("Running PointCloud benchmark..."),await new Promise((K)=>setTimeout(K,10));{let K=NG(1000),W=o(K),X=JSON.stringify(K);V.push({name:"PointCloud (1000 points)",description:"Array of 1000 Point3D structs",cborSize:W.length,jsonSize:X.length,encodeCbor:Z("cboragen",()=>o(K),J),encodeJson:Z("JSON",()=>JSON.stringify(K),J),decodeCbor:Z("cboragen",()=>KG(W),J),decodeJson:Z("JSON",()=>JSON.parse(X),J)})}E("Running Numbers benchmark..."),await new Promise((K)=>setTimeout(K,10));{let K=zG(1e4),W=s(K),X=JSON.stringify(K);V.push({name:"Numbers (10000 f64)",description:"Array of 10000 f64 values",cborSize:W.length,jsonSize:X.length,encodeCbor:Z("cboragen",()=>s(K),J),encodeJson:Z("JSON",()=>JSON.stringify(K),J),decodeCbor:Z("cboragen",()=>OG(W),J),decodeJson:Z("JSON",()=>JSON.parse(X),J)})}E("Done!"),iG(O,V)}p.addEventListener("click",async()=>{p.disabled=!0,u.disabled=!0,VG.innerHTML="";try{await yG(!1)}finally{p.disabled=!1,u.disabled=!1}});u.addEventListener("click",async()=>{p.disabled=!0,u.disabled=!0,VG.innerHTML="";try{await yG(!0)}finally{p.disabled=!1,u.disabled=!1}});var rG=`${navigator.userAgent.split(") ")[0].split("(")[1]||"Unknown browser"}`;RG(`Ready. Browser: ${rG}
Click "Run Benchmarks" to start.`);
