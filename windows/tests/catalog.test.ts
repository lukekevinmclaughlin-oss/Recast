import { describe, expect, it } from "vitest";
import { capabilities, classify, plan, reachable } from "../electron/catalog";

describe("Recast capability graph", () => {
  it("matches the original broad on-device graph", () => {
    expect(capabilities.formatCount).toBeGreaterThanOrEqual(57);
    expect(capabilities.edgeCount).toBeGreaterThanOrEqual(524);
    expect(reachable("png").some((format) => format.id === "pdf")).toBe(true);
    expect(reachable("mp4").some((format) => format.id === "mp3")).toBe(true);
    expect(reachable("docx").some((format) => format.id === "pdf")).toBe(true);
  });

  it("chains routes and classifies compound extensions", () => {
    expect(plan("pdf", "docx")?.map((edge) => `${edge.from}>${edge.to}`)).toEqual(["pdf>txt", "txt>docx"]);
    expect(classify("backup.tar.gz")?.id).toBe("targz");
    expect(classify("photo.JPEG")?.id).toBe("jpeg");
  });
});
