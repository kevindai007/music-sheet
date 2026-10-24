import { readFileSync, renameSync, writeFileSync } from "node:fs";
import { MemoryUsageStore } from "./usage";

/** Node-only: a MemoryUsageStore that survives restarts by writing a small JSON file. */
export class FileUsageStore extends MemoryUsageStore {
  constructor(private readonly path: string) {
    super();
    try {
      const saved = JSON.parse(readFileSync(path, "utf8")) as { day: string; counts: Record<string, number> };
      this.day = saved.day;
      this.counts = new Map(Object.entries(saved.counts));
    } catch {
      // No file yet, or unreadable: start from zero.
    }
  }

  protected override onChange() {
    const tmp = `${this.path}.tmp`;
    writeFileSync(tmp, JSON.stringify({ day: this.day, counts: Object.fromEntries(this.counts) }));
    renameSync(tmp, this.path);
  }
}
