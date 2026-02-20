import type { PropsWithChildren } from 'react';

interface ModalProps {
  title: string;
  isOpen: boolean;
  onClose: () => void;
  className?: string;
}

export const Modal = ({ title, isOpen, onClose, className = '', children }: PropsWithChildren<ModalProps>) => {
  if (!isOpen) return null;

  return (
    <div className="modal-overlay" role="presentation">
      <button type="button" className="modal-dismiss" onClick={onClose} aria-label="Close modal" />
      <section className={`modal glass ${className}`.trim()} role="dialog" aria-modal="true" aria-label={title}>
        <header className="modal-header">
          <h2 className="modal-title">{title}</h2>
        </header>
        <div className="modal-body">{children}</div>
      </section>
    </div>
  );
};
