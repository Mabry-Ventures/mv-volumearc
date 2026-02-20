/** @jest-environment node */

const originalEnv = process.env;
const originalFetch = global.fetch;

describe('telemetryExporter', () => {
  beforeEach(() => {
    jest.resetModules();
    process.env = { ...originalEnv };
    global.fetch = jest.fn();
  });

  afterEach(() => {
    process.env = originalEnv;
    global.fetch = originalFetch;
    jest.clearAllMocks();
  });

  it('skips export when TELEMETRY_EXPORT_URL is not set', async () => {
    delete process.env.TELEMETRY_EXPORT_URL;
    const { telemetryExporter } = await import('@/lib/server/telemetryExporter');
    await telemetryExporter.exportDashboard('telemetry-ingest', 'user:test');
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('exports with bearer token and throttles repeated requests', async () => {
    process.env.TELEMETRY_EXPORT_URL = 'https://telemetry.example.com/ingest';
    process.env.TELEMETRY_EXPORT_TOKEN = 'secret-token';
    process.env.TELEMETRY_EXPORT_MIN_INTERVAL_MS = '600000';

    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({}),
    } as Response);

    const { telemetryExporter } = await import('@/lib/server/telemetryExporter');
    await telemetryExporter.exportDashboard('ai-latency', 'user:test');
    await telemetryExporter.exportDashboard('ai-fallback', 'user:test');

    expect(global.fetch).toHaveBeenCalledTimes(1);
    expect((global.fetch as jest.Mock).mock.calls[0]?.[0]).toBe(
      'https://telemetry.example.com/ingest'
    );
  });
});

