import {ArrowUpRight} from 'lucide-react';

export function MotorFooter() {
  return (
    <footer className="page-footer motor-footer">
      <div className="footer-top">
        <a className="footer-brand" href="#catalogue" aria-label="3 Abdul Motor — kembali ke katalog">
          <img src="./logo-transparent-v2.png" alt="" width="64" height="64" loading="lazy" />
          <span><strong>3 ABDUL MOTOR</strong><small>Jual beli motosikal · Servis & penyelenggaraan</small></span>
        </a>
        <a className="footer-credit" href="https://binalab.my/" target="_blank" rel="noopener noreferrer" aria-label="Lawati website BinaLab (tab baharu)">
          <span className="footer-credit-mark" aria-hidden="true">B<span>.</span></span>
          <span><small>Dibangunkan oleh</small><strong>BinaLab</strong></span>
          <ArrowUpRight size={19} aria-hidden="true" />
        </a>
      </div>
      <div className="footer-bottom">
        <span>© {new Date().getFullYear()} 3 Abdul Motor. Hak cipta terpelihara.</span>
        <span className="footer-signature">Jual beli. Servis. Semua di sini.</span>
      </div>
    </footer>
  );
}
