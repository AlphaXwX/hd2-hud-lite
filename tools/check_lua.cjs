'use strict';
const fs=require('fs'),path=require('path'),lua=require('luaparse');
const root=path.resolve(__dirname,'..');
for(const folder of ['src','tests']) {
  for(const name of fs.readdirSync(path.join(root,folder))) {
    if(!name.endsWith('.lua'))continue;
    lua.parse(fs.readFileSync(path.join(root,folder,name),'utf8'),{luaVersion:'5.1',encodingMode:'x-user-defined'});
  }
}
console.log('Lua 5.1 module syntax passed');
