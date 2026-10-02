import { RefreshCw, X } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';

interface Detector {
  detect(source: HTMLVideoElement): Promise<Array<{ rawValue: string }>>;
}

/**
 * Uses the browser's native BarcodeDetector when available (Chrome/Android), otherwise a WebAssembly
 * polyfill. The WASM file is bundled with the app, so scanning works without reaching a CDN.
 */
async function createDetector(): Promise<Detector> {
  const native = (globalThis as { BarcodeDetector?: new (options: { formats: string[] }) => Detector }).BarcodeDetector;
  if (native) return new native({ formats: ['qr_code'] });

  const [{ BarcodeDetector, prepareZXingModule }, { default: wasmUrl }] = await Promise.all([
    import('barcode-detector/ponyfill'),
    import('zxing-wasm/reader/zxing_reader.wasm?url'),
  ]);
  prepareZXingModule({
    overrides: { locateFile: (path: string, prefix: string) => (path.endsWith('.wasm') ? wasmUrl : prefix + path) },
  });
  return new BarcodeDetector({ formats: ['qr_code'] });
}

export function QrScanner({ onToken, onClose }: { onToken: (token: string) => void; onClose: () => void }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [facing, setFacing] = useState<'user' | 'environment'>('user'); // kiosks usually face the person
  const [problem, setProblem] = useState<string | null>(null);

  useEffect(() => {
    let stream: MediaStream | null = null;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let stopped = false;

    const scan = async (detector: Detector) => {
      const video = videoRef.current;
      if (stopped || !video) return;
      try {
        if (video.readyState >= 2) {
          const codes = await detector.detect(video);
          const token = codes.map((code) => code.rawValue).find((value) => value.startsWith('qr_'));
          if (token && !stopped) {
            stopped = true;
            onToken(token);
            return;
          }
        }
      } catch {
        // a dropped frame is not an error worth showing
      }
      timer = setTimeout(() => void scan(detector), 200);
    };

    void (async () => {
      if (!navigator.mediaDevices?.getUserMedia) {
        setProblem('This browser cannot use the camera. Open the check-in page over HTTPS in Chrome or Safari.');
        return;
      }
      try {
        stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: facing } }, audio: false });
        if (stopped) return;
        const video = videoRef.current;
        if (!video) return;
        video.srcObject = stream;
        await video.play();
        void scan(await createDetector());
      } catch (error) {
        setProblem(
          error instanceof DOMException && error.name === 'NotAllowedError'
            ? 'Camera access is blocked. Allow the camera for this site in the browser settings.'
            : 'The camera could not start. Use the check-in code instead.',
        );
      }
    })();

    return () => {
      stopped = true;
      clearTimeout(timer);
      stream?.getTracks().forEach((track) => track.stop());
    };
  }, [facing, onToken]);

  return (
    <div
      className="fixed inset-0 z-30 flex flex-col items-center justify-center gap-5 bg-ink p-6 text-white"
      role="dialog"
      aria-label="Scan ID card"
    >
      <p className="font-display text-3xl font-semibold">Hold your ID card up to the camera</p>
      <div className="relative aspect-square w-full max-w-md overflow-hidden rounded-3xl bg-black/40">
        <video
          ref={videoRef}
          muted
          playsInline
          className={facing === 'user' ? 'size-full -scale-x-100 object-cover' : 'size-full object-cover'}
        />
        <div className="pointer-events-none absolute inset-10 rounded-2xl border-4 border-white/80" aria-hidden />
      </div>
      {problem && <p className="max-w-md text-center text-lg">{problem}</p>}
      <div className="flex gap-3">
        <Button variant="secondary" size="lg" onClick={() => setFacing(facing === 'user' ? 'environment' : 'user')}>
          <RefreshCw className="size-5" aria-hidden />
          Switch camera
        </Button>
        <Button variant="secondary" size="lg" onClick={onClose}>
          <X className="size-5" aria-hidden />
          Use code instead
        </Button>
      </div>
    </div>
  );
}
