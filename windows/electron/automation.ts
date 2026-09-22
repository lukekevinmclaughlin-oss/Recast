import { promises as fs } from "node:fs";
import path from "node:path";
import { byId, classify, plan } from "./catalog";
import { convertFile, type ConversionOptions } from "./converters";

export const automationUsage = `Recast for Windows — local conversion automation
Recast.exe --convert "C:\\input\\file.docx" --to pdf --output "C:\\output"
Recast.exe --convert "C:\\input\\one.png" "C:\\input\\two.png" --to webp --quality 85 --max-size 1600
Recast.exe --formats

--convert FILE...   Convert the selected local files (no network access).
--to FORMAT         Target format ID from --formats.
--output DIRECTORY  Output directory; otherwise save beside each source.
--quality 10..100    Image quality (default 85).
--max-size PIXELS    Limit the longest image edge without enlarging.
--strip-metadata    Remove image metadata.
--suffix TEXT       Add text to output names.
--report FILE       Write a JSON result report at the chosen path.
Existing source and output files are preserved. Exit code: 0 success, 1 conversion failures, 2 invalid arguments.
`;

export interface AutomationRequest { inputs:string[]; target:string; options:ConversionOptions; report?:string }
export function parseAutomation(args:string[]):AutomationRequest {
  const inputs:string[]=[];
  let target="",report:string|undefined;
  const options:ConversionOptions={imageQuality:.85,resizeEnabled:false,maxDimension:2048,keepMetadata:true,videoQuality:"same",namingSuffix:"",destination:{mode:"next"}};
  for(let index=0;index<args.length;index++){
    const key=args[index];
    if(key==="--convert"){
      while(args[index+1]&&!args[index+1].startsWith("--"))inputs.push(path.resolve(args[++index]));
      continue;
    }
    if(key==="--strip-metadata"){options.keepMetadata=false;continue;}
    if(!["--to","--output","--quality","--max-size","--suffix","--report"].includes(key))throw new Error(`Unknown option: ${key}`);
    const value=args[++index];if(!value||value.startsWith("--"))throw new Error(`Missing value for ${key}`);
    if(key==="--to")target=value.toLowerCase();
    if(key==="--output")options.destination={mode:"folder",folder:path.resolve(value)};
    if(key==="--suffix"){
      if(/[\\/:*?"<>|]/.test(value))throw new Error("The suffix cannot contain filename control characters.");
      options.namingSuffix=value;
    }
    if(key==="--report")report=path.resolve(value);
    if(key==="--quality"){
      const number=Number(value);if(!Number.isFinite(number)||number<10||number>100)throw new Error("Quality must be between 10 and 100.");
      options.imageQuality=number/100;
    }
    if(key==="--max-size"){
      const number=Number(value);if(!Number.isInteger(number)||number<1||number>32768)throw new Error("Maximum size must be between 1 and 32768 pixels.");
      options.maxDimension=number;options.resizeEnabled=true;
    }
  }
  if(!inputs.length)throw new Error("Choose at least one source file with --convert.");
  if(!byId.has(target))throw new Error("Choose a valid --to format.");
  if(report&&inputs.some(file=>file.toLowerCase()===report!.toLowerCase()))throw new Error("The report cannot replace a source file.");
  return {inputs,target,options,report};
}

export async function runAutomation(request:AutomationRequest,signal:AbortSignal){
  const reportFile=request.report?await fs.open(request.report,"wx"):undefined;
  try {
  const results:Array<{input:string;outputPath?:string;outputSize?:number;error?:string}>=[];
  for(const input of request.inputs){
    if(signal.aborted)break;
    try{
      if(!(await fs.stat(input)).isFile())throw new Error("Automation requires individual files.");
      const source=classify(input);
      if(!source||!plan(source.id,request.target)?.length)throw new Error("No supported conversion route for this file and target.");
      results.push({input,...await convertFile(input,source.id,request.target,request.options,signal,()=>undefined)});
    }catch(error){results.push({input,error:error instanceof Error?error.message:String(error)});}
  }
  const report={passed:!signal.aborted&&results.length===request.inputs.length&&results.every(result=>!result.error),results};
  if(reportFile)await reportFile.writeFile(JSON.stringify(report,null,2)+"\n","utf8");
  return report;
  } finally { await reportFile?.close(); }
}
