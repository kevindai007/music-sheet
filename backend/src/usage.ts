/** Per-user count of AI calls, for the daily limit. Days are UTC dates (YYYY-MM-DD). */
export interface UsageStore {
  get(userId: string, day: string): Promise<number>;
  increment(userId: string, day: string): Promise<number>;
  /** Forgets everything about the user (account deletion). */
  delete(userId: string): Promise<void>;
}

export const DEFAULT_DAILY_LIMIT = 20;

export function today(now = new Date()): string {
  return now.toISOString().slice(0, 10);
}

/** Keeps only the current day's counts. `onChange` lets a subclass persist them. */
export class MemoryUsageStore implements UsageStore {
  protected day = "";
  protected counts = new Map<string, number>();

  async get(userId: string, day: string) {
    return day === this.day ? (this.counts.get(userId) ?? 0) : 0;
  }

  async increment(userId: string, day: string) {
    if (day !== this.day) {
      this.day = day;
      this.counts.clear();
    }
    const count = (this.counts.get(userId) ?? 0) + 1;
    this.counts.set(userId, count);
    this.onChange();
    return count;
  }

  async delete(userId: string) {
    if (this.counts.delete(userId)) this.onChange();
  }

  protected onChange() {}
}
