/// <reference types="vite/client" />

interface Window {
  recastNative: {
    capabilities(): Promise<Capabilities>;
    chooseFiles(): Promise<string[]>;
    chooseFolder(): Promise<string | null>;
    inspect(paths: string[]): Promise<{ jobs: NativeJob[]; skipped: number }>;
    pathsForDrop(files: File[]): string[];
    convert(request: ConversionRequest): Promise<{ outputPath: string; outputSize: number }>;
    cancel(id: string): Promise<void>;
    reveal(filePath: string): Promise<void>;
    open(filePath: string): Promise<string>;
    onProgress(listener: (value: { id: string; progress: number }) => void): () => void;
    onChooseFiles(listener: () => void): () => void;
  };
}

type CategoryID = "image" | "audio" | "video" | "document" | "data" | "vector" | "archive" | "ebook";
interface RecastFormat { id: string; name: string; ext: string; aliases: string[]; category: CategoryID }
interface NativeJob { id: string; path: string; fileName: string; source: RecastFormat; target: RecastFormat; targets: RecastFormat[]; size: number }
interface Capabilities { formatCount: number; edgeCount: number; tools: string[]; categories: Array<{ id: CategoryID; title: string }>; formats: RecastFormat[] }
interface ConversionRequest { id: string; path: string; from: string; to: string; options: RecastSettings }
interface RecastSettings {
  imageQuality: number; resizeEnabled: boolean; maxDimension: number; keepMetadata: boolean;
  videoQuality: "same" | "p1080" | "p720"; namingSuffix: string; autoConvert: boolean;
  destination: { mode: "next" | "exports" | "folder"; folder?: string };
  targetByCategory?: Partial<Record<CategoryID,string>>;
}
