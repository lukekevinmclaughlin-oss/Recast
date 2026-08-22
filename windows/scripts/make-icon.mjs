import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import pngToIco from "png-to-ico";

const source = resolve("..", "source", "Resources", "Assets.xcassets", "AppIcon.appiconset", "mac_512.png");
const output = resolve("build", "icon.ico");
await writeFile(output, await pngToIco(await readFile(source)));
