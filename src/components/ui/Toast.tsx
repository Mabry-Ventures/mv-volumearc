interface ToastProps {
  message: string;
  tone?: 'info' | 'success' | 'warning' | 'danger';
  visible: boolean;
}

export const Toast = ({ message, tone = 'info', visible }: ToastProps) => {
  if (!visible) return null;

  return (
    <output className={`toast ${tone}`} aria-live="polite">
      {message}
    </output>
  );
};
