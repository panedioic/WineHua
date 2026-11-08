import { display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import testNapi from 'libentry.so';
import { HgsService, HgsServiceEvent, HgsServiceWindow, HgsSession } from 'hgs';

class HostedWindow {
  latest: HgsServiceWindow;
  host: window.Window | null = null;

  constructor(snapshot: HgsServiceWindow) {
    this.latest = snapshot;
  }
}

export interface X11ImeTarget {
  session: HgsSession;
  windowId: string;
}

// The WineHua probe chooses which windows to host. HGS owns their pixels and
// binds each Surface by session epoch and service window ID.
export class X11ProbeWindowHost {
  private stage: window.WindowStage | null = null;
  private session: HgsSession | null = null;
  private subscription: number = 0;
  private windows: Map<string, HostedWindow> = new Map();
  private imeTarget: X11ImeTarget | null = null;
  private imeListener: ((target: X11ImeTarget | null) => void) | null = null;
  private desktopPid: number = 0;
  private desktopReady: boolean = false;
  private desktopListener: ((ready: boolean) => void) | null = null;

  setDesktopPid(pid: number): void {
    this.desktopPid = pid;
    this.updateDesktopReady();
  }

  private updateDesktopReady(): void {
    let ready = false;
    if (this.desktopPid > 0) {
      this.windows.forEach((entry: HostedWindow): void => {
        const window = entry.latest;
        if (entry.host && window.framePresented && window.title.startsWith('shell - ') &&
          testNapi.matchX11DesktopProcess(this.desktopPid, window.clientPid)) ready = true;
      });
    }
    if (ready !== this.desktopReady) {
      this.desktopReady = ready;
      this.desktopListener?.(ready);
    }
  }

  setImeListener(listener: ((target: X11ImeTarget | null) => void) | null): void {
    this.imeListener = listener;
    listener?.(this.imeTarget);
  }

  private setImeTarget(target: X11ImeTarget | null): void {
    if (this.imeTarget?.windowId === target?.windowId) return;
    this.imeTarget = target;
    this.imeListener?.(target);
  }

  setStage(stage: window.WindowStage | null): void {
    if (this.stage === stage) return;
    this.clearWindows();
    this.setImeTarget(null);
    this.stage = stage;
    if (stage) this.session?.windows().forEach((snapshot: HgsServiceWindow): void => this.update(snapshot));
  }

  start(session: HgsSession, desktopListener: ((ready: boolean) => void) | null = null): void {
    this.stop();
    this.session = session;
    this.desktopListener = desktopListener;
    const service = HgsService.create();
    this.subscription = service.onEvent((event: HgsServiceEvent): void => {
      if (event.epoch !== session.epoch) return;
      if ((event.kind === 'backend-disconnected' && event.origin === 'xwayland') ||
        event.state === 'stopping' || event.state === 'stopped') {
        this.stop();
      } else if (event.kind === 'destroyed') {
        this.close(event.window.id);
      } else if (event.kind === 'created' || event.kind === 'changed') {
        this.update(event.window);
        if (event.window.textInputActive && this.windows.has(event.window.id)) {
          this.setImeTarget({ session: session, windowId: event.window.id });
        } else if (this.imeTarget?.windowId === event.window.id) {
          this.setImeTarget(null);
        }
      }
    });
    session.windows().forEach((snapshot: HgsServiceWindow): void => this.update(snapshot));
  }

  stop(): void {
    if (this.subscription !== 0) HgsService.create().offEvent(this.subscription);
    this.subscription = 0;
    this.session = null;
    this.setDesktopPid(0);
    this.desktopListener = null;
    this.setImeTarget(null);
    this.clearWindows();
  }

  private clearWindows(): void {
    this.windows.forEach((_item: HostedWindow, id: string): void => this.close(id));
  }

  private close(id: string): void {
    if (this.imeTarget?.windowId === id) this.setImeTarget(null);
    const entry = this.windows.get(id);
    this.windows.delete(id);
    this.updateDesktopReady();
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
      const sizeChanged = existing.latest.width !== snapshot.width || existing.latest.height !== snapshot.height;
      existing.latest = snapshot;
      if (existing.host && sizeChanged) {
        void this.resize(existing.host, snapshot).catch((error: Error): void => {
          hilog.warn(0, 'HGS_X11', 'Could not resize %{public}s: %{public}s', snapshot.id, String(error));
        });
      }
      this.updateDesktopReady();
      return;
    }
    const entry = new HostedWindow(snapshot);
    this.windows.set(snapshot.id, entry);
    void this.open(stage, entry);
  }

  private async resize(host: window.Window, snapshot: HgsServiceWindow): Promise<void> {
    const screen = display.getDefaultDisplaySync();
    const scale = Math.min(1, screen.width / snapshot.width, screen.height / snapshot.height);
    await host.resize(Math.max(1, Math.round(snapshot.width * scale)),
      Math.max(1, Math.round(snapshot.height * scale)));
  }

  private async open(stage: window.WindowStage, entry: HostedWindow): Promise<void> {
    const id = entry.latest.id;
    let host: window.Window | null = null;
    try {
      host = await stage.createSubWindowWithOptions(`hgs_x11_${id}`, {
        title: entry.latest.title, decorEnabled: false, isModal: false
      });
      if (this.windows.get(id) !== entry) return;
      await this.resize(host, entry.latest);
      const storage = new LocalStorage();
      storage.setOrCreate<string>('hgsWindowId', id);
      storage.setOrCreate<string>('hgsEpoch', entry.latest.epoch);
      await host.loadContent('pages/X11ProbeWindow', storage);
      if (this.windows.get(id) !== entry) return;
      await host.showWindow();
      if (this.windows.get(id) !== entry) return;
      entry.host = host;
      this.updateDesktopReady();
      hilog.info(0, 'HGS_X11', 'Hosted %{public}s title=%{public}s', id, entry.latest.title);
    } catch (error) {
      if (this.windows.get(id) === entry) this.windows.delete(id);
      hilog.error(0, 'HGS_X11', 'Could not host %{public}s: %{public}s', id, String(error));
    } finally {
      if (host && entry.host !== host) await this.destroy(host);
    }
  }
}
