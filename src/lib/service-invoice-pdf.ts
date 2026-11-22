import {jsPDF} from 'jspdf';
import {money} from './motor';
import type {Job,Payment} from './motor';
import {buildInvoice} from './invoice-model';
import type {InvoiceDoc,InvoiceProfile} from './invoice-model';

export function canShareServiceInvoice(job: Pick<Job, 'status'>) {
  return job.status === 'ready' || job.status === 'collected';
}

/** Downscales the 1343px logo to a small PNG so the PDF stays light. */
export async function loadLogo(url = location.origin + location.pathname + 'logo-320.png'): Promise<string | null> {
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    const canvas = document.createElement('canvas');
    canvas.width = 220;
    canvas.height = Math.round(220 * image.naturalHeight / image.naturalWidth);
    canvas.getContext('2d')?.drawImage(image, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL('image/png');
  } catch {
    return null;
  }
}

const ink: [number, number, number] = [29, 39, 49];
const muted: [number, number, number] = [106, 118, 129];
const line: [number, number, number] = [223, 228, 232];
const tones: Record<string, [[number, number, number], [number, number, number]]> = {
  paid: [[227, 244, 232], [29, 107, 58]], partial: [[255, 243, 214], [138, 90, 0]], due: [[253, 230, 230], [165, 38, 38]],
  draft: [[231, 237, 243], [54, 80, 106]], free: [[236, 239, 242], [74, 85, 96]],
};

/** Vector A4 PDF (selectable, sharp text) with the same layout as the print page. */
export function invoicePdf(doc: InvoiceDoc, logo: string | null): File {
  const pdf = new jsPDF({unit: 'mm', format: 'a4', compress: true});
  pdf.setProperties({title: doc.title + ' ' + doc.number, author: doc.business.name});
  const W = 210, M = 15, R = W - M, bottom = 280;
  let y = 0;
  let page = 1;
  const font = (size: number, bold = false, color = ink) => { pdf.setFont('helvetica', bold ? 'bold' : 'normal'); pdf.setFontSize(size); pdf.setTextColor(...color); };
  const footer = () => {
    pdf.setDrawColor(...line); pdf.line(M, 287, R, 287);
    font(7.5, false, muted);
    pdf.text('Dokumen ini dijana oleh komputer.', M, 291);
    pdf.text(doc.business.name + ' · ' + doc.number + ' · Halaman ' + page, R, 291, {align: 'right'});
  };
  const ensure = (needed: number, header?: () => void) => {
    if (y + needed <= bottom) return;
    footer(); pdf.addPage(); page += 1; y = 18;
    font(8, true, muted); pdf.text(doc.title.toUpperCase() + ' · ' + doc.number + ' (sambungan)', M, y); y += 6;
    header?.();
  };

  // Header: business left, document right.
  let left = M;
  if (logo) { pdf.addImage(logo, 'PNG', M, 14, 22, 19); left = M + 26; }
  font(14, true); pdf.text(doc.business.name.toUpperCase(), left, 19);
  font(8, false, muted);
  let by = 24;
  for (const text of doc.business.lines) for (const part of pdf.splitTextToSize(text, 95)) { pdf.text(part, left, by); by += 3.8; }
  font(19, true); pdf.text(doc.title.toUpperCase(), R, 20, {align: 'right'});
  font(8.5, false, muted);
  const meta: [string, string][] = [['No. dokumen', doc.number], ['Tarikh', doc.issuedAt], ['Rujukan', doc.reference]];
  meta.forEach(([k, v], i) => { font(8.5, false, muted); pdf.text(k, R - 45, 27 + i * 4.5); font(8.5, true); pdf.text(v, R, 27 + i * 4.5, {align: 'right'}); });
  const [bg, fg] = tones[doc.status.tone];
  font(7.5, true, fg);
  const bw = pdf.getTextWidth(doc.status.label) + 6;
  pdf.setFillColor(...bg); pdf.roundedRect(R - bw, 39, bw, 6, 1, 1, 'F'); pdf.text(doc.status.label, R - bw / 2, 43.1, {align: 'center'});
  y = Math.max(by, 48) + 1;
  pdf.setFillColor(232, 185, 35); pdf.rect(M, y, (R - M) * .7, 1.2, 'F'); pdf.setFillColor(216, 49, 43); pdf.rect(M + (R - M) * .7, y, (R - M) * .3, 1.2, 'F');
  y += 6;

  // Parties.
  const boxW = (R - M - 5) / 2;
  const boxLines = (lines: string[]) => lines.flatMap(l => pdf.splitTextToSize(l, boxW - 8) as string[]);
  const a = boxLines(doc.billTo.lines), b = boxLines(doc.subject.lines);
  const boxH = 9 + Math.max(a.length, b.length) * 4.4;
  [[doc.billTo.title, a, M], [doc.subject.title, b, M + boxW + 5]].forEach(([title, rows, x]) => {
    pdf.setDrawColor(...line); pdf.roundedRect(x as number, y, boxW, boxH, 1.5, 1.5, 'S');
    font(7, true, muted); pdf.text((title as string).toUpperCase(), (x as number) + 4, y + 5);
    (rows as string[]).forEach((r, i) => { font(i === 0 && title === doc.billTo.title ? 10 : 9, i === 0 && title === doc.billTo.title); pdf.text(r, (x as number) + 4, y + 10 + i * 4.4); });
  });
  y += boxH + 6;

  // Items table.
  const cols = {no: M + 4, desc: M + 11, qty: 132, unit: 162, amount: R - 3};
  const head = () => {
    pdf.setFillColor(...ink); pdf.rect(M, y, R - M, 7.5, 'F'); font(7.5, true, [255, 255, 255]);
    pdf.text('NO.', cols.no, y + 5, {align: 'center'}); pdf.text('PERKARA', cols.desc, y + 5);
    pdf.text('KUANTITI', cols.qty, y + 5, {align: 'center'}); pdf.text('HARGA SEUNIT', cols.unit, y + 5, {align: 'right'}); pdf.text('AMAUN', cols.amount, y + 5, {align: 'right'});
    y += 7.5;
  };
  head();
  if (!doc.items.length) { font(9, false, muted); pdf.text('Tiada caj direkodkan.', cols.desc, y + 5); y += 8; }
  doc.items.forEach((item, i) => {
    const desc = pdf.splitTextToSize(item.description, 104) as string[];
    const detail = item.detail ? pdf.splitTextToSize(item.detail, 104) as string[] : [];
    const h = 4 + desc.length * 4.3 + detail.length * 3.8 + 2;
    ensure(h, head);
    if (i % 2) { pdf.setFillColor(248, 250, 251); pdf.rect(M, y, R - M, h, 'F'); }
    font(9); pdf.text(String(item.no), cols.no, y + 5, {align: 'center'});
    font(9, true); desc.forEach((d, k) => pdf.text(d, cols.desc, y + 5 + k * 4.3));
    font(7.8, false, muted); detail.forEach((d, k) => pdf.text(d, cols.desc, y + 5 + desc.length * 4.3 + k * 3.8));
    font(9); pdf.text(String(item.qty), cols.qty, y + 5, {align: 'center'}); pdf.text(money(item.unitPrice), cols.unit, y + 5, {align: 'right'}); pdf.text(money(item.amount), cols.amount, y + 5, {align: 'right'});
    y += h; pdf.setDrawColor(...line); pdf.line(M, y, R, y);
  });
  y += 5;

  // Bank details (left) and totals (right).
  const totalsH = doc.totals.length * 6.5;
  ensure(Math.max(totalsH, doc.bank ? doc.bank.length * 4.2 + 9 : 0) + 2);
  const top = y;
  if (doc.bank) {
    pdf.setDrawColor(201, 209, 216); pdf.setLineDashPattern([1, 1], 0); pdf.roundedRect(M, top, 88, doc.bank.length * 4.2 + 8, 1.5, 1.5, 'S'); pdf.setLineDashPattern([], 0);
    font(7, true, muted); pdf.text('CARA BAYARAN', M + 4, top + 5);
    doc.bank.forEach((l, i) => { font(8.5, i === 0); pdf.text(l, M + 4, top + 9.5 + i * 4.2); });
  }
  const tx = R - 80;
  doc.totals.forEach((t, i) => {
    const ty = top + i * 6.5;
    if (t.tone === 'due' && t.strong) { pdf.setFillColor(255, 244, 224); pdf.rect(tx, ty, 80, 6.5, 'F'); }
    if (t.strong) { pdf.setDrawColor(...ink); pdf.setLineWidth(.4); pdf.line(tx, ty, R, ty); pdf.setLineWidth(.2); }
    const color: [number, number, number] = t.tone === 'due' ? [138, 75, 0] : t.tone === 'paid' && !t.strong ? [29, 107, 58] : ink;
    font(t.strong ? 10 : 9, !!t.strong, t.tone === 'due' ? color : ink); pdf.text(t.label, tx + 3, ty + 4.5);
    font(t.strong ? 10 : 9, !!t.strong, color); pdf.text(t.value, R - 3, ty + 4.5, {align: 'right'});
  });
  y = top + Math.max(totalsH, doc.bank ? doc.bank.length * 4.2 + 8 : 0) + 6;

  // Payment ledger.
  if (doc.payments.length) {
    const ledgerHead = () => {
      font(7, true, muted);
      [['RUJUKAN', M], ['TARIKH', M + 22], ['KAEDAH', M + 62], ['DITERIMA OLEH', M + 100]].forEach(([t, x]) => pdf.text(t as string, x as number, y));
      pdf.text('AMAUN', R, y, {align: 'right'}); pdf.setDrawColor(...ink); pdf.line(M, y + 1.5, R, y + 1.5); y += 5.5;
    };
    ensure(16); font(7.5, true, muted); pdf.text(doc.type === 'receipt' ? 'BUTIRAN BAYARAN DITERIMA' : 'SEJARAH BAYARAN', M, y); y += 5;
    ledgerHead();
    for (const p of doc.payments) {
      ensure(6, ledgerHead);
      font(8.3); pdf.text(p.reference, M, y); pdf.text(p.date, M + 22, y); pdf.text(p.method, M + 62, y);
      pdf.text((pdf.splitTextToSize(p.receiver, 45) as string[])[0] || '', M + 100, y); pdf.text(money(p.amount), R, y, {align: 'right'});
      y += 2; pdf.setDrawColor(...line); pdf.line(M, y, R, y); y += 3.8;
    }
    y += 2;
  }

  // Notes and terms.
  for (const note of doc.notes) {
    const rows = pdf.splitTextToSize(note.text, R - M) as string[];
    ensure(8 + Math.min(rows.length, 6) * 3.9);
    font(7, true, muted); pdf.text(note.title.toUpperCase(), M, y + 3); y += 7;
    font(8.5); for (const r of rows) { ensure(4); pdf.text(r, M, y); y += 3.9; }
    y += 2;
  }

  // Signatures pinned near the bottom of the last page.
  ensure(22);
  const sy = Math.max(y + 16, 262);
  doc.signatures.forEach((s, i) => { const x = M + i * 75; pdf.setDrawColor(...ink); pdf.line(x, sy, x + 60, sy); font(8, false, muted); pdf.text(s, x, sy + 4.5); });
  footer();
  return new File([pdf.output('blob')], doc.fileName, {type: 'application/pdf'});
}

export async function serviceInvoicePdf(job: Job, payments: Payment[], profile: InvoiceProfile): Promise<File> {
  if (!canShareServiceInvoice(job)) throw Error('Job perlu berstatus Siap atau Diserahkan.');
  return invoicePdf(buildInvoice(job, payments, 'invoice', profile), await loadLogo());
}
