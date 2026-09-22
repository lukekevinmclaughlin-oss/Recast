import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, readFile, writeFile, cp, copyFile, rm, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const vendor=join(root,'vendor');
const officeHash='4aa6c6e1895f4055104effcb556bd3362d20c6ad707c149543304f395ef9db95';
const pandocHash='2ab72baf2399450e148ddf7a2a8689806c42e1bba71862b57e220fd9b8456d3d';
const digest=data=>createHash('sha256').update(data).digest('hex');
async function matches(file,expected){try{return digest(await readFile(file))===expected;}catch{return false;}}
async function run(file,args){await new Promise((resolve,reject)=>{const child=spawn(file,args,{windowsHide:true,stdio:'inherit'});child.once('error',reject);child.once('close',code=>code===0?resolve():reject(new Error(`${file} exited ${code}`)));});}
async function download(url,file,expected){const response=await fetch(url,{signal:AbortSignal.timeout(300000)});if(!response.ok)throw new Error(`Engine download returned ${response.status}`);const data=Buffer.from(await response.arrayBuffer());if(digest(data)!==expected)throw new Error('Engine archive checksum mismatch');await writeFile(file,data);}
const office=join(vendor,'libreoffice');
const pandoc=join(vendor,'pandoc');
const officeReady=await matches(join(office,'program','soffice.com'),'95016b59e08da1e6cbb02fc8f027593c076bf47df795092578afdd995306ac85')
  && await matches(join(office,'program','soffice.bin'),'6e3e16a5c8338138ea14666f7873b8f909eebf266fcacb4bb840906ca115c62e')
  && await access(join(office,'.recast-prepared')).then(()=>true).catch(()=>false);
const pandocReady=await matches(join(pandoc,'pandoc.exe'),'e0057eaf640d08ba028b70721d4f7b63a685c30430de9db89aea84de2d4a1912')
  && await matches(join(pandoc,'COPYRIGHT.txt'),'43575d901fd50cc06f49042b82f114667a82c17d63b429e99635ae9430c977c4')
  && await matches(join(pandoc,'COPYING.rtf'),'b2e44b72220d84e7ec7d5c7ed2b76e42b2c239ae1f179a2a2a9a34d1e40f315e');
if(officeReady&&pandocReady)console.log('Pinned local LibreOffice and Pandoc engines verified.');
else {
  if(process.platform!=='win32'||process.arch!=='x64')throw new Error('Document engines require Windows x64.');
  const temporary=await mkdtemp(join(tmpdir(),'recast-document-engines-'));
  try {
    if(!officeReady){
      const archive=join(temporary,'LibreOffice.msi');
      await download('https://download.documentfoundation.org/libreoffice/stable/26.8.0/win/x86_64/LibreOffice_26.8.0_Win_x86-64.msi',archive,officeHash);
      const unpacked=join(temporary,'office');
      // Administrative extraction copies the engine; it does not install or
      // register LibreOffice, change file associations, or alter system PATH.
      await run('msiexec.exe',['/a',archive,'/qn','/norestart',`TARGETDIR=${unpacked}`]);
      await mkdir(office,{recursive:true});
      for(const name of ['program','share','presets','Fonts','readmes'])await cp(join(unpacked,name),join(office,name),{recursive:true});
      for(const name of ['LICENSE.html','license.txt','NOTICE'])await copyFile(join(unpacked,name),join(office,name));
      await writeFile(join(office,'.recast-prepared'),officeHash+'\n');
    }
    if(!pandocReady){
      const archive=join(temporary,'pandoc.zip');
      await download('https://github.com/jgm/pandoc/releases/download/3.11/pandoc-3.11-windows-x86_64.zip',archive,pandocHash);
      await run('tar.exe',['-xf',archive,'-C',temporary,'pandoc-3.11/pandoc.exe','pandoc-3.11/COPYRIGHT.txt','pandoc-3.11/COPYING.rtf']);
      await mkdir(pandoc,{recursive:true});
      for(const name of ['pandoc.exe','COPYRIGHT.txt','COPYING.rtf'])await copyFile(join(temporary,'pandoc-3.11',name),join(pandoc,name));
    }
    console.log('Document engines prepared locally; no system installation, GitHub Actions or LFS.');
  } finally {await rm(temporary,{recursive:true,force:true});}
}
