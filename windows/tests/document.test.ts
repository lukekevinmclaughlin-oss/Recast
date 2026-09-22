import { beforeAll, afterAll, describe, expect, it } from "vitest";
import { promises as fs } from "node:fs";
import path from "node:path";
import os from "node:os";
import { createServer } from "node:http";
import { once } from "node:events";
import AdmZip from "adm-zip";
import { Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell } from "docx";
import { convertFile, type ConversionOptions } from "../electron/converters";
let root = "";
const options = (): ConversionOptions => ({imageQuality:1,resizeEnabled:false,maxDimension:2048,keepMetadata:true,videoQuality:"same",namingSuffix:"",destination:{mode:"folder",folder:root}});
const convert = (input:string,from:string,to:string) => convertFile(input,from,to,options(),new AbortController().signal,()=>undefined);
beforeAll(async()=>{root=await fs.mkdtemp(path.join(os.tmpdir(),"recast-rich-test-"));});
afterAll(async()=>{await fs.rm(root,{recursive:true,force:true});});

describe("native rich document conversions",()=>{
  it("preserves Unicode through PDF and genuine binary DOC",async()=>{
    const input=path.join(root,"Unicode.txt");
    const text="Grüße — café Ελληνικά 日本語";
    await fs.writeFile(input,text,"utf8");
    const pdf=await convert(input,"txt","pdf");
    const extracted=await convert(pdf.outputPath,"pdf","txt");
    const restored=await fs.readFile(extracted.outputPath,"utf8");
    expect(restored).toContain("Grüße"); expect(restored).toContain("Ελληνικά"); expect(restored).toContain("日本語");
    const doc=await convert(input,"txt","doc");
    expect((await fs.readFile(doc.outputPath)).subarray(0,8)).toEqual(Buffer.from([0xd0,0xcf,0x11,0xe0,0xa1,0xb1,0x1a,0xe1]));
    const back=await convert(doc.outputPath,"doc","txt");
    expect(await fs.readFile(back.outputPath,"utf8")).toContain(text);
  },120_000);

  it("preserves rich text and tables through DOCX, RTF and ODT",async()=>{
    const input=path.join(root,"styled.docx");
    const document=new Document({sections:[{children:[
      new Paragraph({text:"Heading",heading:HeadingLevel.HEADING_1}),
      new Paragraph({children:[new TextRun({text:"Bold café",bold:true}),new TextRun({text:" italic",italics:true})]}),
      new Table({rows:[new TableRow({children:[new TableCell({children:[new Paragraph("Cell one")]}),new TableCell({children:[new Paragraph("Cell two")]})]})]}),
    ]}]});
    await fs.writeFile(input,await Packer.toBuffer(document));
    for(const type of ["rtf","odt"]) {
      const intermediate=await convert(input,"docx",type);
      const restored=await convert(intermediate.outputPath,type,"docx");
      const xml=new AdmZip(restored.outputPath).readAsText("word/document.xml");
      expect(xml).toContain("Bold café"); expect(xml).toContain("Cell one");
      expect(xml).toMatch(/<w:b(?:\s|\/|>)/); expect(xml).toMatch(/<w:i(?:\s|\/|>)/); expect(xml).toContain("<w:tbl>");
    }
  },120_000);

  it("handles real Markdown, EPUB, Org, reStructuredText and LaTeX syntax",async()=>{
    const input=path.join(root,"markup.md");
    await fs.writeFile(input,"# Title\n\nA **bold** paragraph with café.\n\n- One\n- Two\n");
    for(const type of ["epub","org","rst","tex"]){
      const output=await convert(input,"md",type);
      const restored=await convert(output.outputPath,type,"docx");
      const xml=new AdmZip(restored.outputPath).readAsText("word/document.xml");
      expect(xml).toContain("bold"); expect(xml).toMatch(/<w:b(?:\s|\/|>)/); expect(xml).toContain("café");
    }
  },120_000);

  it("imports RTF Unicode and UTF-16 plain text without losing characters",async()=>{
    const rtf=path.join(root,"Unicode.rtf");
    await fs.writeFile(rtf,String.raw`{\rtf1\ansi\ansicpg1252\uc1\b Caf\'e9\b0\par\u26085?\u26412?\u35486?}`,"ascii");
    const text=await convert(rtf,"rtf","txt");
    const converted=await fs.readFile(text.outputPath,"utf8");
    expect(converted).toContain("Café");expect(converted).toContain("日本語");
    const utf16=path.join(root,"UTF16.txt");
    await fs.writeFile(utf16,Buffer.concat([Buffer.from([0xff,0xfe]),Buffer.from("Grüße — 日本語","utf16le")]));
    const docx=await convert(utf16,"txt","docx");
    expect(new AdmZip(docx.outputPath).readAsText("word/document.xml")).toContain("日本語");
  },120_000);

  it("does not fetch external HTML content or silently include unrelated local files",async()=>{
    let requests=0;
    const server=createServer((_req,res)=>{requests++;res.end("PRIVATE CONTENT");});
    server.listen(0,"127.0.0.1");await once(server,"listening");
    try{
      const port=(server.address() as {port:number}).port;
      const input=path.join(root,"remote.html");
      await fs.writeFile(input,`<h1>Offline document</h1><iframe src="http://127.0.0.1:${port}/secret"></iframe><img src="http://127.0.0.1:${port}/image.png">`);
      const output=await convert(input,"html","docx");
      const xml=new AdmZip(output.outputPath).readAsText("word/document.xml");
      expect(xml).toContain("Offline document");expect(xml).not.toContain("PRIVATE CONTENT");expect(requests).toBe(0);
    }finally{server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));}
  },120_000);
});
