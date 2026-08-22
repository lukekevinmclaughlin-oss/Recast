import { useCallback, useEffect, useMemo, useRef, useState, type DragEvent, type ReactNode } from "react";
import {
  Archive, BookOpen, Braces, CheckCircle2, ChevronDown, CircleX, Database,
  FileText, Film, Folder, FolderOpen, Images, LockKeyhole, Music2, OctagonX, Play, RotateCw,
  ScanLine, Settings2, Shapes, ShieldCheck, Sparkles, Trash2, X,
} from "lucide-react";
import icon from "./assets/recast-icon.png";

type JobStatus = "ready" | "queued" | "running" | "done" | "failed" | "cancelled";
interface Job extends NativeJob { status: JobStatus; progress: number; outputPath?: string; outputSize?: number; error?: string }

const defaultSettings: RecastSettings = {
  imageQuality: 0.85, resizeEnabled: false, maxDimension: 2048, keepMetadata: true,
  videoQuality: "same", namingSuffix: "", autoConvert: true, destination: { mode: "next" },
};
const colors: Record<CategoryID, string> = { image: "#4fe9f5", audio: "#b98cff", video: "#ff8a5b", document: "#5b8cff", data: "#54e39b", vector: "#ffc24d", archive: "#9aa6b2", ebook: "#ff6fb5" };
const categoryIcons: Record<CategoryID, typeof Images> = { image: Images, audio: Music2, video: Film, document: FileText, data: Braces, vector: Shapes, archive: Archive, ebook: BookOpen };
const loadSettings = (): RecastSettings => { try { return { ...defaultSettings, ...JSON.parse(localStorage.getItem("recast.settings.v1") ?? "{}") }; } catch { return defaultSettings; } };
const bytes = (value?: number) => value == null ? "" : value < 1024 ? `${value} bytes` : value < 1_048_576 ? `${(value / 1024).toFixed(value < 10_240 ? 1 : 0)} KB` : value < 1_073_741_824 ? `${(value / 1_048_576).toFixed(1)} MB` : `${(value / 1_073_741_824).toFixed(1)} GB`;

function IconButton({ title, children, onClick, disabled }: { title: string; children: ReactNode; onClick(): void; disabled?: boolean }) {
  return <button className="icon-button" title={title} aria-label={title} onClick={onClick} disabled={disabled}>{children}</button>;
}

function FormatSelect({ job, onChange }: { job: Job; onChange(value: RecastFormat): void }) {
  const groups = useMemo(() => {
    const grouped = new Map<CategoryID, RecastFormat[]>();
    for (const format of job.targets) grouped.set(format.category, [...(grouped.get(format.category) ?? []), format]);
    return [...grouped.entries()];
  }, [job.targets]);
  return <label className="format-select" style={{ "--target": colors[job.target.category] } as React.CSSProperties}>
    <select value={job.target.id} onChange={(event) => { const target = job.targets.find((item) => item.id === event.target.value); if (target) onChange(target); }}>
      {groups.map(([category, formats]) => <optgroup key={category} label={category.toUpperCase()}>{formats.map((format) => <option key={format.id} value={format.id}>{format.name}</option>)}</optgroup>)}
    </select><ChevronDown />
  </label>;
}

function JobRow({ job, update, start, cancel, remove }: { job: Job; update(format: RecastFormat): void; start(): void; cancel(): void; remove(): void }) {
  const Icon = categoryIcons[job.source.category];
  const statusColor = job.status === "done" ? "#54e39b" : job.status === "failed" ? "#ffc24d" : colors[job.source.category];
  return <article className={`job-row ${job.status}`} style={{ "--job": statusColor } as React.CSSProperties}>
    <span className="job-icon"><Icon /></span>
    <div className="job-copy"><strong title={job.fileName}>{job.fileName}</strong><div className="job-route"><span className="format-badge" style={{ "--format": colors[job.source.category] } as React.CSSProperties}>{job.source.name}</span><i>to</i><FormatSelect job={job} onChange={update} /></div>
      <small>{bytes(job.size)}{job.outputSize != null ? ` to ${bytes(job.outputSize)}` : ""}{job.error ? ` / ${job.error}` : ""}</small>
    </div>
    <div className="job-actions">
      {job.status === "ready" && <button className="convert-button" onClick={start}><Play /> Convert</button>}
      {job.status === "queued" && <span className="queued-label"><RotateCw /> queued</span>}
      {job.status === "running" && <><div className="job-progress"><div><i style={{ width: `${Math.round(job.progress * 100)}%` }} /></div><span>{Math.round(job.progress * 100)}%</span></div><IconButton title="Cancel conversion" onClick={cancel}><CircleX /></IconButton></>}
      {job.status === "done" && <><IconButton title="Reveal converted file" onClick={() => job.outputPath && void window.recastNative.reveal(job.outputPath)}><FolderOpen /></IconButton><button className="done-button" title="Open converted file" onClick={() => job.outputPath && void window.recastNative.open(job.outputPath)}><CheckCircle2 /></button></>}
      {job.status === "failed" && <span className="failed-icon" title={job.error}><OctagonX /></span>}
      {job.status === "cancelled" && <span className="cancelled-label">cancelled</span>}
      <IconButton title="Remove from queue" onClick={remove}><X /></IconButton>
    </div>
  </article>;
}

function SettingsPanel({ settings, setSettings, close }: { settings: RecastSettings; setSettings(value: RecastSettings): void; close(): void }) {
  const patch = <K extends keyof RecastSettings>(key: K, value: RecastSettings[K]) => setSettings({ ...settings, [key]: value });
  const pickFolder = async () => { const folder = await window.recastNative.chooseFolder(); if (folder) patch("destination", { mode: "folder", folder }); };
  return <div className="modal-backdrop" onMouseDown={(event) => { if (event.currentTarget === event.target) close(); }}><section className="settings-panel"><header><div><Settings2 /><span><strong>Settings</strong><small>Windows conversion engines</small></span></div><IconButton title="Close settings" onClick={close}><X /></IconButton></header><div className="settings-scroll">
    <fieldset><legend>General</legend><label className="toggle-row"><span><strong>Convert automatically on drop</strong><small>Start each recognized file as soon as it joins the queue.</small></span><input type="checkbox" checked={settings.autoConvert} onChange={(event) => patch("autoConvert", event.target.checked)} /></label></fieldset>
    <fieldset><legend>Images</legend><label className="range-row"><span>Quality <b>{Math.round(settings.imageQuality * 100)}%</b></span><input type="range" min="0.1" max="1" step="0.01" value={settings.imageQuality} onChange={(event) => patch("imageQuality", Number(event.target.value))} /></label><label className="toggle-row"><span><strong>Resize to a maximum size</strong><small>Constrain the longest edge without enlarging smaller images.</small></span><input type="checkbox" checked={settings.resizeEnabled} onChange={(event) => patch("resizeEnabled", event.target.checked)} /></label>{settings.resizeEnabled && <label className="range-row"><span>Longest edge <b>{settings.maxDimension}px</b></span><input type="range" min="320" max="8192" step="64" value={settings.maxDimension} onChange={(event) => patch("maxDimension", Number(event.target.value))} /></label>}<label className="toggle-row"><span><strong>Keep EXIF and metadata</strong></span><input type="checkbox" checked={settings.keepMetadata} onChange={(event) => patch("keepMetadata", event.target.checked)} /></label></fieldset>
    <fieldset><legend>Video</legend><label className="select-row"><span>Quality</span><select value={settings.videoQuality} onChange={(event) => patch("videoQuality", event.target.value as RecastSettings["videoQuality"])}><option value="same">Same quality</option><option value="p1080">1080p</option><option value="p720">720p</option></select></label></fieldset>
    <fieldset><legend>Output</legend><label className="text-row"><span>Filename suffix</span><input value={settings.namingSuffix} placeholder="e.g. -converted" onChange={(event) => patch("namingSuffix", event.target.value.replace(/[\\/:*?"<>|]/g, ""))} /></label><label className="select-row"><span>Save converted files</span><select value={settings.destination.mode} onChange={(event) => { const mode = event.target.value as "next" | "exports" | "folder"; if (mode === "folder") void pickFolder(); else patch("destination", { mode }); }}><option value="next">Next to original</option><option value="exports">Documents / Recast Exports</option><option value="folder">Choose a folder...</option></select></label>{settings.destination.mode === "folder" && <button className="folder-path" onClick={() => void pickFolder()}><Folder />{settings.destination.folder}</button>}</fieldset>
    <fieldset><legend>Recast Pro</legend><div className="access-active"><ShieldCheck /><span><strong>Full Windows access active</strong><small>Batch conversion, folder intake, presets, and automation are enabled.</small></span></div></fieldset>
  </div></section></div>;
}

export default function App() {
  const [capabilities, setCapabilities] = useState<Capabilities | null>(null); const [jobs, setJobs] = useState<Job[]>([]); const [settings, setSettings] = useState(loadSettings);
  const [settingsOpen, setSettingsOpen] = useState(false); const [dragging, setDragging] = useState(false); const [notice, setNotice] = useState("");
  const active = useRef(new Set<string>());
  useEffect(() => { void window.recastNative.capabilities().then(setCapabilities); return window.recastNative.onProgress(({ id, progress }) => setJobs((current) => current.map((job) => job.id === id ? { ...job, progress } : job))); }, []);
  useEffect(() => { localStorage.setItem("recast.settings.v1", JSON.stringify(settings)); }, [settings]);

  const addPaths = useCallback(async (paths: string[]) => {
    if (!paths.length) return; const result = await window.recastNative.inspect(paths);
    if (result.skipped) { setNotice(`${result.skipped} unsupported file${result.skipped === 1 ? "" : "s"} skipped`); setTimeout(() => setNotice(""), 3500); }
    const incoming = result.jobs.map<Job>((job) => ({ ...job, status: settings.autoConvert ? "queued" : "ready", progress: 0 }));
    setJobs((current) => [...current, ...incoming]);
  }, [settings.autoConvert]);
  const chooseFiles = useCallback(async () => addPaths(await window.recastNative.chooseFiles()), [addPaths]);
  useEffect(() => window.recastNative.onChooseFiles(() => void chooseFiles()), [chooseFiles]);

  const run = useCallback(async (job: Job) => {
    if (active.current.has(job.id)) return; active.current.add(job.id);
    setJobs((current) => current.map((item) => item.id === job.id ? { ...item, status: "running", progress: 0, error: undefined } : item));
    try {
      const result = await window.recastNative.convert({ id: job.id, path: job.path, from: job.source.id, to: job.target.id, options: settings });
      setJobs((current) => current.map((item) => item.id === job.id ? { ...item, ...result, status: "done", progress: 1 } : item));
    } catch (error) {
      setJobs((current) => current.map((item) => item.id === job.id ? { ...item, status: item.status === "cancelled" ? "cancelled" : "failed", error: String((error as Error).message ?? error) } : item));
    } finally { active.current.delete(job.id); }
  }, [settings]);
  useEffect(() => { if (!jobs.some((job) => job.status === "running")) { const next = jobs.find((job) => job.status === "queued" && !active.current.has(job.id)); if (next) void run(next); } }, [jobs, run]);

  const updateJob = (id: string, transform: (job: Job) => Job) => setJobs((current) => current.map((job) => job.id === id ? transform(job) : job));
  const retarget = (id: string, target: RecastFormat) => updateJob(id, (job) => ({ ...job, target, status: job.status === "done" ? "queued" : job.status, outputPath: job.status === "done" ? undefined : job.outputPath, outputSize: job.status === "done" ? undefined : job.outputSize }));
  const start = (id: string) => updateJob(id, (job) => ({ ...job, status: "queued" }));
  const cancel = (id: string) => { updateJob(id, (job) => ({ ...job, status: "cancelled" })); void window.recastNative.cancel(id); };
  const remove = (id: string) => { void window.recastNative.cancel(id); setJobs((current) => current.filter((job) => job.id !== id)); };
  const unfinished = jobs.filter((job) => !["done", "failed", "cancelled"].includes(job.status));
  const commonTargets = useMemo(() => unfinished.length < 2 ? [] : unfinished[0].targets.filter((format) => unfinished.every((job) => job.targets.some((candidate) => candidate.id === format.id))), [unfinished]);
  const convertAll = (targetId: string) => { const target = capabilities?.formats.find((format) => format.id === targetId); if (!target) return; setJobs((current) => current.map((job) => job.status === "done" ? job : { ...job, target, status: "queued" })); };
  const drop = (event: DragEvent) => { event.preventDefault(); setDragging(false); void addPaths(window.recastNative.pathsForDrop([...event.dataTransfer.files])); };

  return <main className="recast-app" onDragOver={(event) => { event.preventDefault(); setDragging(true); }} onDragLeave={(event) => { if (event.currentTarget === event.target) setDragging(false); }} onDrop={drop}>
    <section className="control-pane"><header className="brand"><img src={icon} alt="" /><div><h1>Recast</h1><span>Any file to any format</span></div><em>PRO</em></header>
      <div className="capabilities"><span><b>{capabilities?.formatCount ?? "-"}</b> formats</span><i /><span><b>{capabilities?.edgeCount ?? "-"}</b> conversions</span><i /><small><Sparkles />{capabilities?.tools.join(" / ")}</small></div>
      <button className={`drop-zone ${dragging ? "targeted" : ""}`} onClick={() => void chooseFiles()}><span className="reticle"><i /><i /><i /><i /><ScanLine /></span><strong>{dragging ? "Release to convert" : "Drop files to convert"}</strong><small>Images, audio, video, documents, data</small></button>
      {notice && <div className="notice">{notice}</div>}
      <button className="destination" onClick={() => setSettingsOpen(true)}><Folder /><span>Save to</span><strong>{settings.destination.mode === "next" ? "Next to original" : settings.destination.mode === "exports" ? "Recast Exports" : settings.destination.folder?.split(/[\\/]/).at(-1)}</strong><ChevronDown /></button>
      <div className="control-actions"><button className="choose-button" onClick={() => void chooseFiles()}><FolderOpen /> Choose Files</button><IconButton title="Conversion settings" onClick={() => setSettingsOpen(true)}><Settings2 /></IconButton></div>
      <footer><LockKeyhole /> <span>100% on-device. Files never leave your PC.</span></footer>
    </section>
    <section className="queue-pane">{jobs.length ? <><header className="queue-header"><div><span>QUEUE</span><b>{jobs.length}</b></div><div>{jobs.filter((job) => job.status === "ready").length > 1 && <button onClick={() => setJobs((current) => current.map((job) => job.status === "ready" ? { ...job, status: "queued" } : job))}>Convert {jobs.filter((job) => job.status === "ready").length}</button>}{commonTargets.length > 0 && <label className="batch-select"><select defaultValue="" onChange={(event) => { convertAll(event.target.value); event.target.value = ""; }}><option value="" disabled>Convert all</option>{commonTargets.map((format) => <option key={format.id} value={format.id}>{format.name}</option>)}</select><ChevronDown /></label>}{jobs.some((job) => ["done", "failed", "cancelled"].includes(job.status)) && <button onClick={() => setJobs((current) => current.filter((job) => !["done", "failed", "cancelled"].includes(job.status)))}>Clear done</button>}<button onClick={() => { jobs.forEach((job) => void window.recastNative.cancel(job.id)); setJobs([]); }}><Trash2 /> Clear all</button></div></header><div className="queue-list">{[...jobs].reverse().map((job) => <JobRow key={job.id} job={job} update={(format) => retarget(job.id, format)} start={() => start(job.id)} cancel={() => cancel(job.id)} remove={() => remove(job.id)} />)}</div></> : <div className="empty-state"><Database /><h2>Drop anything to begin</h2><p>Recast routes each file through the best local engine and chains steps when a target needs them.</p><div className="category-grid">{(capabilities?.categories ?? []).map((category) => { const Icon = categoryIcons[category.id]; return <div key={category.id} style={{ "--category": colors[category.id] } as React.CSSProperties}><Icon /><span>{category.title}</span></div>; })}</div></div>}</section>
    {settingsOpen && <SettingsPanel settings={settings} setSettings={setSettings} close={() => setSettingsOpen(false)} />}
  </main>;
}
