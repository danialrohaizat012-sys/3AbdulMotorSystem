import {useState} from 'react';
import {Download, FileText, MessageCircle, Share2} from 'lucide-react';
import {normalizePhone} from '../lib/business';
import {jobId} from '../lib/motor';
import {getRecord} from '../lib/records';

type PreparedInvoice = {file: File; whatsappUrl: string};

export function ServiceInvoiceShare({id}: {id: number}) {
  const [invoice, setInvoice] = useState<PreparedInvoice | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function prepare() {
    setBusy(true);
    setError('');
    try {
      const [job, {serviceInvoicePdf}] = await Promise.all([
        getRecord('jobs', id),
        import('../lib/service-invoice-pdf'),
      ]);
      if ('brand' in job) throw Error('Job servis tidak dijumpai.');
      const phone = normalizePhone(job.phone);
      const message = 'Salam ' + (job.customer || 'tuan/puan') + ', ini invois servis ' + jobId(job.id) +
        ' untuk ' + job.bike + (job.plate ? ' (' + job.plate + ')' : '') + '. Terima kasih daripada 3 Abdul Motor.';
      setInvoice({
        file: serviceInvoicePdf(job),
        whatsappUrl: /^[1-9][0-9]{7,14}$/.test(phone)
          ? 'https://wa.me/' + phone + '?text=' + encodeURIComponent(message)
          : '',
      });
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'PDF gagal dijana.');
    } finally {
      setBusy(false);
    }
  }

  async function share(file: File) {
    setError('');
    try {
      await navigator.share({files: [file], title: 'Invois servis 3 Abdul Motor'});
    } catch (cause) {
      if (!(cause instanceof DOMException && cause.name === 'AbortError')) {
        setError('Kongsi fail tidak berjaya. Muat turun PDF dan lampirkan dalam WhatsApp.');
      }
    }
  }

  function download(file: File) {
    const url = URL.createObjectURL(file);
    const link = document.createElement('a');
    link.href = url;
    link.download = file.name;
    link.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
  }

  return <section className="operation-panel" aria-label="Invois pelanggan">
    <h3>Invois pelanggan</h3>
    {invoice ? <>
      <p className="form-note">PDF sedia. Untuk WhatsApp Web, muat turun PDF, buka chat pelanggan dan lampirkan fail.</p>
      <div className="action-row">
        {typeof navigator.share === 'function' && navigator.canShare?.({files: [invoice.file]}) &&
          <button className="btn primary" onClick={() => void share(invoice.file)}><Share2 size={16}/>Kongsi PDF</button>}
        <button className="btn subtle" onClick={() => download(invoice.file)}><Download size={16}/>Muat turun PDF</button>
        {invoice.whatsappUrl && <a className="btn subtle" href={invoice.whatsappUrl} target="_blank" rel="noopener noreferrer"><MessageCircle size={16}/>WhatsApp pelanggan</a>}
      </div>
    </> : <button className="btn primary" disabled={busy} onClick={() => void prepare()}><FileText size={16}/>{busy ? 'Menjana PDF…' : 'Sediakan PDF pelanggan'}</button>}
    {error && <p className="form-error" role="alert">{error}</p>}
  </section>;
}
