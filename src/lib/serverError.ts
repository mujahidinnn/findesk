export function serverErrorKey(err: { code?: string; message?: string } | null | undefined): string {
  if (err?.message && /^[A-Z][A-Z0-9_]+$/.test(err.message)) return err.message;
  switch (err?.code) {
    case "23505":
      return "DUPLICATE";
    case "23503":
      return "IN_USE";
    case "23514":
    case "23502":
    case "22P02":
      return "INVALID";
    case "42501":
      return "FORBIDDEN";
    default:
      return "UNKNOWN";
  }
}
