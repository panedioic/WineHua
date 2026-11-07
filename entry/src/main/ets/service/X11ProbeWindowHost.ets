import { display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HgsService, HgsServiceEvent, HgsServiceWindow, HgsSession } from 'hgs';

class HostedWindow {
  latest: HgsServiceWindow;
  host: window.Window | null = null;

  constructor(snapshot: HgsServiceWindow) {
    this.latest = snapshot;
  }
}

// The WineHua probe chooses which windows to host. HGS owns their pixels and
// binds each Surface by session epoch and service window ID.
export class X11ProbeWindowHost {
  private stage: window.WindowStage | null = null;
  private session: HgsSession | null = null;
  private subscription: number = 0;
  private windows: Map<string, HostedWindow> = new Map();

  setStage(stage: window.WindowStage | null): void {
    if (this.stage === stage) return;
    this.clearWindows();
    this.stage = stage;
    if (stage) this.session?.windows().forEach((snapshot: HgsServiceWindow): void => this.update(snapshot));
  }

  start(session: HgsSession): void {
    this.stop();
    this.session = session;
    const service = HgsService.create();
    this.subscription = service.onEvent((event: HgsServiceEvent): void => {
      if (event.epoch !== session.epoch) return;
      if (event.kind === 'backend-disconnected' || event.state === 'stopping' || event.state === 'stopped') {
        this.stop();
      } else if (event.kind === 'destroyed') {
        this.close(event.window.id);
      } else if (event.kind === 'created' || event.kind === 'changed') {
        this.update(event.window);
      }
    });
    session.windows().forEach((snapshot: HgsServiceWindow): void => this.update(snapshot));
  }

  stop(): void {
    if (this.subscription !== 0) HgsService.create().offEvent(this.subscription);
    this.subscription = 0;
    this.session = null;
    this.clearWindows();
  }

  private clearWindows(): void {
    this.windows.forEach((_item: HostedWindow, id: string): void => this.close(id));
  }

  private close(id: string): void {
    const entry = this.windows.get(id);
    this.windows.delete(id);
    if (entry?.host) void this.destroy(entry.host);
  }

  private async destroy(host: window.Window): Promise<void> {
    try { await host.destroyWindow(); } catch (_) { /* Stage may already be gone. */ }
  }

  private update(snapshot: HgsServiceWindow): void {
    const stage = this.stage;
    if (!stage || snapshot.protocol !== 'x11' || snapshot.role !== 'toplevel') return;
    if (!snapshot.visible || snapshot.width <= 0 || snapshot.height <= 0) {
      this.close(snapshot.id);
      return;
    }
    const existing = this.windows.get(snapshot.id);
    if (existing) {
      existing.latest = snapshot;
      return;
    }
    const entry = new HostedWindow(snapshot);
    this.windows.set(snapshot.id, entry);
    void this.open(stage, entry);
  }

  private async open(stage: window.WindowStage, entry: HostedWindow): Promise<void> {
    const id = entry.latest.id;
    let host: window.Window | null = null;
    try {
      host = await stage.createSubWindowWithOptions(`hgs_x11_${id}`, {
        title: entry.latest.title, decorEnabled: false, isModal: false
      });
      if (this.windows.get(id) !== entry) return;
      const screen = display.getDefaultDisplaySync();
      const scale = Math.min(1, screen.width / entry.latest.width, screen.height / entry.latest.height);
      await host.resize(Math.max(1, Math.round(entry.latest.width * scale)),
        Math.max(1, Math.round(entry.latest.height * scale)));
      const storage = new LocalStorage();
      storage.setOrCreate<string>('hgsWindowId', id);
      storage.setOrCreate<string>('hgsEpoch', entry.latest.epoch);
      await host.loadContent('pages/X11ProbeWindow', storage);
      if (this.windows.get(id) !== entry) return;
      await host.showWindow();
      if (this.windows.get(id) !== entry) return;
      entry.host = host;
      hilog.info(0, 'HGS_X11', 'Hosted %{public}s title=%{public}s', id, entry.latest.title);
    } catch (error) {
      if (this.windows.get(id) === entry) this.windows.delete(id);
      hilog.error(0, 'HGS_X11', 'Could not host %{public}s: %{public}s', id, String(error));
    } finally {
      if (host && entry.host !== host) await this.destroy(host);
    }
  }
}
