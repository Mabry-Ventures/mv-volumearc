import type { PropsWithChildren } from 'react';

interface CardProps {
  className?: string;
  elevated?: boolean;
}

export const Card = ({ children, className = '', elevated = false }: PropsWithChildren<CardProps>) => {
  return (
    <section className={`card ${elevated ? 'card-elevated' : ''} ${className}`.trim()}>
      {children}
    </section>
  );
};
