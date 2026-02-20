import type { PropsWithChildren } from 'react';

interface SheetProps {
  title: string;
  isOpen: boolean;
  onClose: () => void;
  className?: string;
}

export const Sheet = ({ title, isOpen, onClose, className = '', children }: PropsWithChildren<SheetProps>) => {
  if (!isOpen) return null;

  return (
    <div className="sheet-overlay" role="presentation">
      <button type="button" className="sheet-dismiss" onClick={onClose} aria-label="Close panel" />
      <section className={`sheet ${className}`.trim()} role="dialog" aria-modal="true" aria-label={title}>
        <header className="sheet-header">
          <h2>{title}</h2>
        </header>
        <div className="sheet-body">{children}</div>
      </section>
    </div>
  );
};
