import type { Download } from './http';

/** Saves a Blob through a temporary link. */
export function saveDownload({ blob, fileName }: Download): void {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1_000);
}

export function saveText(text: string, fileName: string, type = 'text/csv;charset=utf-8'): void {
  saveDownload({ blob: new Blob([text], { type }), fileName });
}
