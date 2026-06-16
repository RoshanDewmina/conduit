export function EmptyState({ message }: { message: string }) {
  return (
    <div className="flex items-center justify-center p-12">
      <p className="text-sm text-muted-foreground font-mono">{message}</p>
    </div>
  );
}
