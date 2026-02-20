import { telemetryStore } from '@/lib/server/telemetryStore';

describe('telemetryStore', () => {
  it('ingests ui events and computes dashboard summary', () => {
    telemetryStore.ingestUiEvents(
      [
        {
          id: 'evt-1',
          version: '1.0.0',
          stage: 'workout_active',
          action: 'set_complete_toggle',
          elapsedMs: 82,
          createdAt: new Date().toISOString(),
          actorId: 'user:test',
        },
      ],
      'user:test'
    );

    const summary = telemetryStore.getDashboardSummary();
    expect(summary.counts.uiEvents).toBeGreaterThan(0);
    expect(summary.kpis.setLogLatencyMs.p50).not.toBeNull();
  });
});
