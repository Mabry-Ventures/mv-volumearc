import { telemetryStore } from '@/lib/server/telemetryStore';

type ExportReason = 'telemetry-ingest' | 'ai-latency' | 'ai-fallback';

const exportUrl = process.env.TELEMETRY_EXPORT_URL?.trim();
const exportToken = process.env.TELEMETRY_EXPORT_TOKEN?.trim();
const minIntervalMs = Number(process.env.TELEMETRY_EXPORT_MIN_INTERVAL_MS || 30_000);

let lastExportAt = 0;

export const telemetryExporter = {
  async exportDashboard(reason: ExportReason, actorId?: string): Promise<void> {
    if (!exportUrl) return;

    const now = Date.now();
    if (now - lastExportAt < minIntervalMs) return;
    lastExportAt = now;

    try {
      await fetch(exportUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(exportToken ? { Authorization: `Bearer ${exportToken}` } : {}),
        },
        body: JSON.stringify({
          reason,
          actorId: actorId || null,
          summary: telemetryStore.getDashboardSummary(),
          exportedAt: new Date().toISOString(),
        }),
        cache: 'no-store',
      });
    } catch {
      // Best-effort exporter. Local telemetry remains available.
    }
  },
};

