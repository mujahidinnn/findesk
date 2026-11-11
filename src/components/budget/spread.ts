export function spreadEvenly(annual: number): number[] {
  const base = Math.trunc(annual / 12);
  return Array.from({ length: 12 }, (_, i) => (i === 11 ? annual - base * 11 : base));
}
