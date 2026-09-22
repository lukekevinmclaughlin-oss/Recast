import { expect,it } from "vitest";
import { promises as fs } from "node:fs";
import path from "node:path";
import os from "node:os";
import { parseAutomation,runAutomation } from "../electron/automation";

it("automation reports real conversion results and preserves an existing report",async()=>{
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),"recast-cli-test-"));
  try{
    const input=path.join(directory,"data.json"),report=path.join(directory,"report.json");
    await fs.writeFile(input,'[{"name":"Ada","score":99}]');
    const request=parseAutomation(["--convert",input,"--to","csv","--report",report]);
    const result=await runAutomation(request,new AbortController().signal);
    expect(result.passed).toBe(true);
    expect(await fs.readFile(result.results[0].outputPath!,"utf8")).toContain("Ada");
    const saved=await fs.readFile(report,"utf8");
    await expect(runAutomation(request,new AbortController().signal)).rejects.toMatchObject({code:"EEXIST"});
    expect(await fs.readFile(report,"utf8")).toBe(saved);
    expect(()=>parseAutomation(["--convert",input,"--to","csv","--report",input])).toThrow("source file");
  }finally{await fs.rm(directory,{recursive:true,force:true});}
});
