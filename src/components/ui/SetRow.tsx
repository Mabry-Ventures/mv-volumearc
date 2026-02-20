import type { ReactNode } from 'react';

interface SetRowProps {
  setNumber: number;
  previous?: string;
  weightInput: ReactNode;
  repsInput: ReactNode;
  completeAction: ReactNode;
  quickActions?: ReactNode;
}

export const SetRow = ({
  setNumber,
  previous,
  weightInput,
  repsInput,
  completeAction,
  quickActions,
}: SetRowProps) => {
  return (
    <div className="set-row-enhanced">
      <div className="set-meta">
        <div className="set-index">#{setNumber}</div>
        {previous && <div className="set-previous">Prev {previous}</div>}
      </div>
      <div className="set-fields">
        {weightInput}
        {repsInput}
      </div>
      <div className="set-actions">
        {completeAction}
        {quickActions}
      </div>
    </div>
  );
};
