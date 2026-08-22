import { app, BrowserWindow, dialog, ipcMain, Menu, nativeImage, session, shell, Tray } from "electron";
import { promises as fs } from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { capabilities, categories, classify, defaultTarget, formats, graph, reachable } from "./catalog";
import { convertFile, type ConversionOptions } from "./converters";

let mainWindow: BrowserWindow | null = null;
let tray: Tray | null = null;
let quitting = false;
const conversions = new Map<string, AbortController>();

function iconPath(): string { return path.join(app.getAppPath(), "build", "icon.ico"); }

function showWindow(): void {
  if (!mainWindow) return;
  mainWindow.show(); mainWindow.restore(); mainWindow.focus();
}

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1120, height: 720, minWidth: 900, minHeight: 620, show: false,
    title: "Recast", backgroundColor: "#07101d", icon: iconPath(),
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true, nodeIntegration: false, sandbox: true },
  });
  mainWindow.removeMenu();
  void mainWindow.loadFile(path.join(app.getAppPath(), "dist", "index.html"));
  mainWindow.once("ready-to-show", () => mainWindow?.show());
  mainWindow.on("close", (event) => { if (!quitting) { event.preventDefault(); mainWindow?.hide(); } });
}

function createTray(): void {
  const image = nativeImage.createFromPath(iconPath()).resize({ width: 20, height: 20 });
  tray = new Tray(image); tray.setToolTip("Recast - on-device file converter");
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: "Open Recast", click: showWindow },
    { label: "Choose files...", click: () => { showWindow(); mainWindow?.webContents.send("tray:choose-files"); } },
    { type: "separator" },
    { label: "Quit", click: () => { quitting = true; app.quit(); } },
  ]));
  tray.on("double-click", showWindow);
}

async function expand(input: string): Promise<string[]> {
  const stat = await fs.stat(input).catch(() => null); if (!stat) return [];
  if (stat.isFile()) return [input]; if (!stat.isDirectory()) return [];
  const entries = await fs.readdir(input, { withFileTypes: true });
  const nested = await Promise.all(entries.filter((entry) => !entry.name.startsWith(".")).map((entry) => expand(path.join(input, entry.name))));
  return nested.flat();
}

async function inspectPaths(paths: string[]) {
  const expanded = (await Promise.all(paths.map(expand))).flat();
  const jobs = [];
  for (const filePath of expanded) {
    const source = classify(filePath); if (!source) continue;
    const targets = reachable(source.id); if (!targets.length) continue;
    jobs.push({ id: randomUUID(), path: filePath, fileName: path.basename(filePath), source, target: defaultTarget(source), targets, size: (await fs.stat(filePath)).size });
  }
  return { jobs, skipped: expanded.length - jobs.length };
}

function registerIpc(): void {
  ipcMain.handle("recast:capabilities", () => ({ ...capabilities, categories, formats, edgeCount: graph.length }));
  ipcMain.handle("recast:choose-files", async () => {
    const result = await dialog.showOpenDialog(mainWindow!, { properties: ["openFile", "multiSelections"], title: "Choose files to convert" });
    return result.canceled ? [] : result.filePaths;
  });
  ipcMain.handle("recast:choose-folder", async () => {
    const result = await dialog.showOpenDialog(mainWindow!, { properties: ["openDirectory", "createDirectory"], title: "Choose output folder" });
    return result.canceled ? null : result.filePaths[0];
  });
  ipcMain.handle("recast:inspect", (_event, paths: string[]) => inspectPaths(paths));
  ipcMain.handle("recast:convert", async (event, request: { id: string; path: string; from: string; to: string; options: ConversionOptions }) => {
    const controller = new AbortController(); conversions.set(request.id, controller);
    try {
      return await convertFile(request.path, request.from, request.to, request.options, controller.signal, (progress) => event.sender.send("recast:progress", { id: request.id, progress }));
    } finally { conversions.delete(request.id); }
  });
  ipcMain.handle("recast:cancel", (_event, id: string) => { conversions.get(id)?.abort(); });
  ipcMain.handle("recast:reveal", (_event, filePath: string) => shell.showItemInFolder(filePath));
  ipcMain.handle("recast:open", (_event, filePath: string) => shell.openPath(filePath));
}

app.whenReady().then(() => {
  session.defaultSession.webRequest.onHeadersReceived((details, callback) => callback({ responseHeaders: { ...details.responseHeaders, "Content-Security-Policy": ["default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self';"] } }));
  registerIpc(); createWindow(); createTray();
  app.on("activate", showWindow);
});
app.on("before-quit", () => { quitting = true; for (const controller of conversions.values()) controller.abort(); });
app.on("window-all-closed", () => { /* The Windows tray surface remains active. */ });
