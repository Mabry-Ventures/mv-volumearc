interface StatsCardProps {
  value: string | number;
  label: string;
  icon?: React.ReactNode;
}

export const StatsCard = ({ value, label, icon }: StatsCardProps) => {
  return (
    <div className="stat-card">
      {icon && <div className="mb-2">{icon}</div>}
      <div className="stat-value">{value}</div>
      <div className="stat-label">{label}</div>
    </div>
  );
};
