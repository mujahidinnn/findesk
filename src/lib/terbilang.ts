const ONES = ["", "satu", "dua", "tiga", "empat", "lima", "enam", "tujuh", "delapan", "sembilan", "sepuluh", "sebelas"];
const SCALES: [number, string][] = [
  [1e12, "triliun"],
  [1e9, "miliar"],
  [1e6, "juta"],
  [1e3, "ribu"],
];

function words(n: number): string {
  if (n < 12) return ONES[n];
  if (n < 20) return `${ONES[n - 10]} belas`;
  if (n < 100) return `${ONES[Math.floor(n / 10)]} puluh ${words(n % 10)}`.trim();
  if (n < 200) return `seratus ${words(n - 100)}`.trim();
  if (n < 1000) return `${ONES[Math.floor(n / 100)]} ratus ${words(n % 100)}`.trim();
  for (const [size, name] of SCALES) {
    if (n >= size) {
      const head = Math.floor(n / size);
      const lead = size === 1e3 && head === 1 ? "seribu" : `${words(head)} ${name}`;
      return `${lead} ${words(n % size)}`.trim();
    }
  }
  return "";
}

export function terbilang(amount: number, unit = "rupiah"): string {
  const abs = Math.abs(Math.round(amount * 100)) / 100;
  const whole = Math.floor(abs);
  const cents = Math.round((abs - whole) * 100);
  const text = [whole === 0 ? "nol" : words(whole), unit, cents ? `${words(cents)} sen` : ""].filter(Boolean).join(" ");
  return amount < 0 ? `minus ${text}` : text;
}
