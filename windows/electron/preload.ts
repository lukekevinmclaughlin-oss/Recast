import { contextBridge, ipcRenderer, webUtils } from "electron";

contextBridge.exposeInMainWorld("recastNative", {
  capabilities: () => ipcRenderer.invoke("recast:capabilities"),
  chooseFiles: () => ipcRenderer.invoke("recast:choose-files"),
  chooseFolder: () => ipcRenderer.invoke("recast:choose-folder"),
  inspect: (paths: string[]) => ipcRenderer.invoke("recast:inspect", paths),
  pathsForDrop: (files: File[]) => files.map((file) => webUtils.getPathForFile(file)).filter(Boolean),
  convert: (request: unknown) => ipcRenderer.invoke("recast:convert", request),
  cancel: (id: string) => ipcRenderer.invoke("recast:cancel", id),
  reveal: (filePath: string) => ipcRenderer.invoke("recast:reveal", filePath),
  open: (filePath: string) => ipcRenderer.invoke("recast:open", filePath),
  onProgress: (listener: (value: { id: string; progress: number }) => void) => {
    const handler = (_event: Electron.IpcRendererEvent, value: { id: string; progress: number }) => listener(value);
    ipcRenderer.on("recast:progress", handler); return () => ipcRenderer.removeListener("recast:progress", handler);
  },
  onChooseFiles: (listener: () => void) => {
    const handler = () => listener(); ipcRenderer.on("tray:choose-files", handler); return () => ipcRenderer.removeListener("tray:choose-files", handler);
  },
});
