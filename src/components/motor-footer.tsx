import {ArrowUpRight} from 'lucide-react';

export function MotorFooter() {
  return (
    <footer className="page-footer motor-footer">
      <span>© {new Date().getFullYear()} 3 Abdul Motor</span>
      <a className="footer-credit" href="https://binalab.my/" target="_blank" rel="noopener noreferrer" aria-label="Lawati website BinaLab (tab baharu)">
        <span>Built by <b>BinaLab</b></span>
        <ArrowUpRight size={12} aria-hidden="true" />
      </a>
    </footer>
  );
}
