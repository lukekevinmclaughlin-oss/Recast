import path from "node:path";

export type CategoryID = "image" | "audio" | "video" | "document" | "data" | "vector" | "archive" | "ebook";
export interface Format { id: string; name: string; ext: string; aliases: string[]; category: CategoryID }
export interface Edge { from: string; to: string; backend: "image" | "media" | "pdf" | "data" | "document" | "archive"; cost: number }

const f = (id: string, name: string, ext: string, category: CategoryID, aliases: string[] = []): Format => ({ id, name, ext, category, aliases });
export const formats: Format[] = [
  f("jpeg", "JPEG", "jpg", "image", ["jpeg", "jpe"]), f("png", "PNG", "png", "image"),
  f("heic", "HEIC", "heic", "image", ["heif"]), f("tiff", "TIFF", "tiff", "image", ["tif"]),
  f("gif", "GIF", "gif", "image"), f("bmp", "BMP", "bmp", "image"), f("webp", "WebP", "webp", "image"),
  f("ico", "ICO", "ico", "image"), f("icns", "Apple Icon", "icns", "image"), f("avif", "AVIF", "avif", "image"),
  f("jxl", "JPEG XL", "jxl", "image"), f("psd", "Photoshop", "psd", "image"), f("tga", "Targa", "tga", "image"),
  f("ppm", "PPM", "ppm", "image"), f("svg", "SVG", "svg", "vector"), f("eps", "EPS", "eps", "vector"),
  f("mp3", "MP3", "mp3", "audio"), f("m4a", "M4A (AAC)", "m4a", "audio"), f("aac", "AAC", "aac", "audio"),
  f("wav", "WAV", "wav", "audio"), f("aiff", "AIFF", "aiff", "audio", ["aif"]), f("caf", "CAF", "caf", "audio"),
  f("flac", "FLAC", "flac", "audio"), f("ogg", "OGG", "ogg", "audio", ["oga"]), f("opus", "Opus", "opus", "audio"),
  f("wma", "WMA", "wma", "audio"), f("mp4", "MP4", "mp4", "video", ["m4v"]), f("mov", "MOV", "mov", "video"),
  f("mkv", "MKV", "mkv", "video"), f("webm", "WebM", "webm", "video"), f("avi", "AVI", "avi", "video"),
  f("flv", "FLV", "flv", "video"), f("wmv", "WMV", "wmv", "video"), f("mpg", "MPEG", "mpg", "video", ["mpeg"]),
  f("gifv", "Animated GIF", "gif", "video"), f("pdf", "PDF", "pdf", "document"),
  f("docx", "Word (docx)", "docx", "document"), f("doc", "Word (doc)", "doc", "document"),
  f("odt", "OpenDocument", "odt", "document"), f("rtf", "RTF", "rtf", "document"), f("rtfd", "RTFD", "rtfd", "document"),
  f("html", "HTML", "html", "document", ["htm"]), f("txt", "Plain Text", "txt", "document", ["text"]),
  f("md", "Markdown", "md", "document", ["markdown"]), f("rst", "reStructuredText", "rst", "document"),
  f("tex", "LaTeX", "tex", "document", ["latex"]), f("org", "Org", "org", "document"), f("epub", "EPUB", "epub", "ebook"),
  f("json", "JSON", "json", "data"), f("yaml", "YAML", "yaml", "data", ["yml"]), f("xml", "XML", "xml", "data"),
  f("plist", "Property List", "plist", "data"), f("csv", "CSV", "csv", "data"), f("tsv", "TSV", "tsv", "data"),
  f("toml", "TOML", "toml", "data"), f("zip", "ZIP", "zip", "archive"), f("tar", "TAR", "tar", "archive"),
  f("targz", "TAR.GZ", "tar.gz", "archive", ["tgz"]), f("gz", "Gzip", "gz", "archive"),
];

export const byId = new Map(formats.map((format) => [format.id, format]));
export const categories: Array<{ id: CategoryID; title: string }> = [
  { id: "image", title: "Images" }, { id: "audio", title: "Audio" }, { id: "video", title: "Video" },
  { id: "document", title: "Documents" }, { id: "data", title: "Data" }, { id: "vector", title: "Vector" },
  { id: "archive", title: "Archives" }, { id: "ebook", title: "eBooks" },
];

const edges: Edge[] = [];
const add = (from: string, to: string, backend: Edge["backend"], cost = 1) => {
  if (from !== to) edges.push({ from, to, backend, cost });
};
const matrix = (sources: string[], targets: string[], backend: Edge["backend"], cost: number) => {
  for (const source of sources) for (const target of targets) add(source, target, backend, cost);
};

const imageRead = ["jpeg", "png", "heic", "tiff", "gif", "bmp", "webp", "ico", "icns", "avif", "jxl", "psd", "tga", "ppm", "svg"];
const imageWrite = ["jpeg", "png", "heic", "tiff", "gif", "bmp", "webp", "ico", "avif", "jxl", "tga", "ppm"];
matrix(imageRead, imageWrite, "image", 1);
for (const source of imageRead) add(source, "pdf", "image", 1.2);
for (const target of ["png", "jpeg", "tiff"]) add("pdf", target, "pdf", 1.4);
add("pdf", "txt", "pdf", 1.3);

const audio = ["mp3", "m4a", "aac", "wav", "aiff", "caf", "flac", "ogg", "opus", "wma"];
const video = ["mp4", "mov", "mkv", "webm", "avi", "flv", "wmv", "mpg"];
matrix(audio, audio, "media", 2);
matrix(video, video, "media", 2);
matrix(video, audio, "media", 2.1);
for (const source of video) add(source, "gifv", "media", 2.2);

const data = ["json", "yaml", "xml", "plist", "csv", "tsv", "toml"];
matrix(data, data, "data", 1);
const documents = ["txt", "html", "md", "rst", "tex", "org", "rtf", "rtfd", "doc", "docx", "odt", "epub"];
matrix(documents, documents, "document", 1.4);
for (const source of documents) add(source, "pdf", "document", 1.5);

const archiveTargets = ["zip", "tar", "targz", "gz"];
for (const source of formats.filter((format) => format.category !== "archive")) {
  for (const target of archiveTargets) add(source.id, target, "archive", 2.5);
}

const best = new Map<string, Edge>();
for (const edge of edges) {
  const key = `${edge.from}>${edge.to}`;
  if (!best.has(key) || best.get(key)!.cost > edge.cost) best.set(key, edge);
}
export const graph = [...best.values()];

export function classify(filePath: string): Format | undefined {
  const lower = path.basename(filePath).toLowerCase();
  if (lower.endsWith(".tar.gz") || lower.endsWith(".tgz")) return byId.get("targz");
  const extension = path.extname(lower).slice(1);
  return formats.find((format) => format.id !== "gifv" && [format.ext, ...format.aliases].includes(extension));
}

export function plan(from: string, to: string): Edge[] | undefined {
  if (from === to) return [];
  const distance = new Map<string, number>([[from, 0]]);
  const previous = new Map<string, Edge>();
  const pending = new Set<string>([from]);
  while (pending.size) {
    const node = [...pending].sort((a, b) => (distance.get(a) ?? Infinity) - (distance.get(b) ?? Infinity))[0];
    pending.delete(node);
    if (node === to) break;
    for (const edge of graph.filter((candidate) => candidate.from === node)) {
      const next = (distance.get(node) ?? Infinity) + edge.cost;
      if (next < (distance.get(edge.to) ?? Infinity)) {
        distance.set(edge.to, next); previous.set(edge.to, edge); pending.add(edge.to);
      }
    }
  }
  if (!distance.has(to)) return undefined;
  const route: Edge[] = [];
  let current = to;
  while (current !== from) {
    const edge = previous.get(current);
    if (!edge) return undefined;
    route.unshift(edge); current = edge.from;
  }
  return route;
}

export function reachable(from: string): Format[] {
  return formats.filter((format) => format.id !== from && plan(from, format.id)).sort((a, b) => a.category.localeCompare(b.category) || a.name.localeCompare(b.name));
}

export function defaultTarget(source: Format): Format {
  const preferred: Record<CategoryID, string> = { image: "jpeg", audio: "mp3", video: "mp4", document: "pdf", data: "json", vector: "png", archive: "zip", ebook: "pdf" };
  const target = byId.get(preferred[source.category]);
  if (target && target.id !== source.id && plan(source.id, target.id)) return target;
  return reachable(source.id).find((item) => item.category === source.category) ?? reachable(source.id)[0] ?? source;
}

export const capabilities = {
  formatCount: new Set(graph.flatMap((edge) => [edge.from, edge.to])).size,
  edgeCount: graph.length,
  tools: ["Sharp", "FFmpeg", "PDF.js", "local document + data engines"],
};
