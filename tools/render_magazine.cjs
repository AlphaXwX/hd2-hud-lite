'use strict';
const fs=require('fs'),path=require('path');
const {Resvg}=require('@resvg/resvg-js');
const root=path.resolve(__dirname,'..');
const out=path.join(root,'assets');fs.mkdirSync(out,{recursive:true});
const input=path.join(root,'assets','icon-pack','magazine','Magazine_Icon.svg');
const source=fs.readFileSync(input);
// Credit metadata belongs in THIRD_PARTY_NOTICES.md, not inside the asset.
const cleaned=Buffer.from(source.toString('utf8').replace(/<desc>[\s\S]*?<\/desc>\s*/i,''));
// Original transparent viewBox and white paths, no reconstructed artwork.
const result=new Resvg(cleaned,{fitTo:{mode:'width',value:512}}).render();
fs.writeFileSync(path.join(out,'Magazine_Icon.svg'),cleaned);
fs.writeFileSync(path.join(out,'Magazine_Icon.png'),result.asPng());
console.log('SVG converted:',result.width,result.height,'transparent PNG');
