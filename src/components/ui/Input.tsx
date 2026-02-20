import type { InputHTMLAttributes } from 'react';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  helperText?: string;
}

export const Input = ({ id, label, helperText, className = '', ...props }: InputProps) => {
  return (
    <div className="input-group">
      {label && (
        <label className="label" htmlFor={id}>
          {label}
        </label>
      )}
      <input id={id} className={`input ${className}`.trim()} {...props} />
      {helperText && <p className="input-helper">{helperText}</p>}
    </div>
  );
};
