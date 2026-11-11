import { describe, expect, it } from "vitest";
import { terbilang } from "../terbilang";

describe("terbilang", () => {
  it("spells rupiah amounts", () => {
    expect(terbilang(1250000)).toBe("satu juta dua ratus lima puluh ribu rupiah");
    expect(terbilang(0)).toBe("nol rupiah");
    expect(terbilang(11)).toBe("sebelas rupiah");
    expect(terbilang(115)).toBe("seratus lima belas rupiah");
    expect(terbilang(1000)).toBe("seribu rupiah");
    expect(terbilang(1999)).toBe("seribu sembilan ratus sembilan puluh sembilan rupiah");
    expect(terbilang(21000)).toBe("dua puluh satu ribu rupiah");
    expect(terbilang(100000)).toBe("seratus ribu rupiah");
    expect(terbilang(1000000)).toBe("satu juta rupiah");
    expect(terbilang(2500000000)).toBe("dua miliar lima ratus juta rupiah");
    expect(terbilang(1000000000000)).toBe("satu triliun rupiah");
  });
  it("handles cents, other units and negatives", () => {
    expect(terbilang(1250.5, "dolar AS")).toBe("seribu dua ratus lima puluh dolar AS lima puluh sen");
    expect(terbilang(-12)).toBe("minus dua belas rupiah");
  });
});
