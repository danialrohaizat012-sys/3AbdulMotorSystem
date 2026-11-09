import {jsPDF} from 'jspdf';
import {dateText, jobId, jobStatuses, money, parseLines, paymentStatus, total} from './motor';
import type {Job} from './motor';

export function canShareServiceInvoice(job: Pick<Job, 'status'>) {
  return job.status === 'ready' || job.status === 'collected';
}

export function serviceInvoicePdf(job: Job): File {
  if (!canShareServiceInvoice(job)) throw Error('Job perlu berstatus Siap atau Diserahkan.');

  const width = 794;
  const height = 1123;
  const margin = 52;
  const bottom = height - 65;
  const id = jobId(job.id);
  const canvas = document.createElement('canvas');
  canvas.width = width * 2;
  canvas.height = height * 2;
  const context = canvas.getContext('2d');
  if (!context) throw Error('Pelayar tidak dapat menjana PDF.');
  const ctx = context;
  ctx.scale(2, 2);
  ctx.textBaseline = 'top';

  const pdf = new jsPDF({unit: 'mm', format: 'a4', compress: true});
  pdf.setProperties({title: 'Invois servis ' + id, author: '3 Abdul Motor'});
  let page = 0;
  let y = 0;

  function text(value: string, x: number, top: number, size = 16, bold = false, align: CanvasTextAlign = 'left') {
    ctx.font = (bold ? 'bold ' : '') + size + 'px Arial, sans-serif';
    ctx.fillStyle = '#17212a';
    ctx.textAlign = align;
    ctx.fillText(value, x, top);
  }

  function rule(top: number) {
    ctx.fillStyle = '#dce2e7';
    ctx.fillRect(margin, top, width - 2 * margin, 1);
  }

  function finishPage() {
    rule(height - 50);
    text('3 Abdul Motor  ·  ' + id, margin, height - 40, 12);
    text('Halaman ' + page, width - margin, height - 40, 12, false, 'right');
    pdf.addImage(canvas.toDataURL('image/jpeg', 0.94), 'JPEG', 0, 0, 210, 297);
  }

  function startPage() {
    if (page) {
      finishPage();
      pdf.addPage();
    }
    page += 1;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, width, height);
    text('3 ABDUL MOTOR', margin, 43, 30, true);
    text('INVOIS SERVIS  /  ' + id, margin, 84, 17, true);
    ctx.fillStyle = '#e8c067';
    ctx.fillRect(margin, 114, width - 2 * margin, 4);
    y = 138;
  }

  function wrap(value: string, maxWidth: number) {
    ctx.font = '16px Arial, sans-serif';
    const lines: string[] = [];
    for (const paragraph of value.split(/\r?\n/)) {
      let line = '';
      for (const word of paragraph.trim().split(/\s+/)) {
        const candidate = line ? line + ' ' + word : word;
        if (ctx.measureText(candidate).width <= maxWidth) {
          line = candidate;
        } else {
          if (line) lines.push(line);
          line = '';
          for (const character of word) {
            if (ctx.measureText(line + character).width > maxWidth) {
              lines.push(line);
              line = '';
            }
            line += character;
          }
        }
      }
      lines.push(line);
    }
    return lines;
  }

  function paragraph(value: string) {
    for (const line of wrap(value, width - 2 * margin)) {
      if (y + 23 > bottom) startPage();
      text(line, margin, y);
      y += 23;
    }
  }

  function tableHeading() {
    ctx.fillStyle = '#f0f3f5';
    ctx.fillRect(margin, y, width - 2 * margin, 34);
    text('Butiran', margin + 10, y + 9, 14, true);
    text('Kuantiti', 477, y + 9, 14, true, 'right');
    text('Harga', 603, y + 9, 14, true, 'right');
    text('Jumlah', width - margin - 10, y + 9, 14, true, 'right');
    y += 43;
  }

  startPage();
  paragraph('Tarikh invois: ' + dateText(new Date().toISOString()));
  paragraph('Pelanggan: ' + (job.customer || '—'));
  paragraph('Motosikal: ' + [job.bike, job.plate].filter(Boolean).join(' / '));
  paragraph('Status kerja: ' + jobStatuses[job.status]);
  y += 18;
  if (y + 75 > bottom) startPage();
  tableHeading();

  const items = parseLines(job.items);
  if (!items.length) paragraph('Tiada caj servis.');
  for (const item of items) {
    const lines = wrap(item.name + ' · ' + (item.kind === 'part' ? 'Alat ganti' : 'Upah'), 345);
    if (y + Math.min(lines.length * 22 + 13, 80) > bottom) {
      startPage();
      tableHeading();
    }
    text(String(item.qty), 477, y, 16, false, 'right');
    text(money(item.rate), 603, y, 16, false, 'right');
    text(money(item.qty * item.rate), width - margin - 10, y, 16, false, 'right');
    for (const line of lines) {
      if (y + 22 > bottom) {
        startPage();
        tableHeading();
      }
      text(line, margin + 10, y);
      y += 22;
    }
    rule(y + 1);
    y += 13;
  }

  const amount = total(job);
  if (y + 124 > bottom) startPage();
  y += 14;
  for (const [label, value] of [
    ['Jumlah servis', amount],
    ['Dibayar', job.paid],
    ['Baki', Math.max(0, amount - job.paid)],
  ] as const) {
    text(label, 555, y, 16, label === 'Baki', 'right');
    text(money(value), width - margin, y, 16, label === 'Baki', 'right');
    y += 24;
  }
  text(paymentStatus(job.paid, amount), width - margin, y + 4, 14, false, 'right');
  finishPage();

  return new File([pdf.output('blob')], 'Invois-Servis-' + id + '.pdf', {type: 'application/pdf'});
}
