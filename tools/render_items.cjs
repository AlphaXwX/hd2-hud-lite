'use strict';
const fs=require('fs'),path=require('path');
const {Resvg}=require('@resvg/resvg-js');
const root=path.resolve(__dirname,'..');
for(const name of ['cura','grenade']){
  const file=path.join(root,'assets','icon-pack','consumables',name+'.svg');
  const source=fs.readFileSync(file,'utf8');
  const cleaned=source.replace(/<desc>[\s\S]*?<\/desc>\s*/gi,'');
  const result=new Resvg(cleaned,{fitTo:{mode:'width',value:512}}).render();
  fs.writeFileSync(path.join(root,'assets',name+'.png'),result.asPng());
  console.log('Consumable SVG converted:',name,result.width,result.height);
}
