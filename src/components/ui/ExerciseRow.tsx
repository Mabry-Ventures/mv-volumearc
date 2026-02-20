import type { PropsWithChildren, ReactNode } from 'react';

interface ExerciseRowProps {
  title: string;
  subtitle?: string;
  rightSlot?: ReactNode;
  className?: string;
}

export const ExerciseRow = ({
  title,
  subtitle,
  rightSlot,
  className = '',
  children,
}: PropsWithChildren<ExerciseRowProps>) => {
  return (
    <section className={`exercise-row ${className}`.trim()}>
      <header className="exercise-row-header">
        <div>
          <h3 className="exercise-row-title">{title}</h3>
          {subtitle && <p className="exercise-row-subtitle">{subtitle}</p>}
        </div>
        {rightSlot}
      </header>
      {children}
    </section>
  );
};
