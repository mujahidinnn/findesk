import { describe, expect, it } from "vitest";
import { serverErrorKey } from "../serverError";

describe("serverErrorKey", () => {
  it("passes business codes through", () => {
    expect(serverErrorKey({ code: "23514", message: "INSUFFICIENT_STOCK" })).toBe("INSUFFICIENT_STOCK");
    expect(serverErrorKey({ code: "P0001", message: "APPROVAL_SELF" })).toBe("APPROVAL_SELF");
  });

  it("maps Postgres codes when the message is a sentence", () => {
    expect(serverErrorKey({ code: "23505", message: 'duplicate key value violates unique constraint "m_taxes_code_key"' })).toBe("DUPLICATE");
    expect(serverErrorKey({ code: "23503", message: "violates foreign key constraint" })).toBe("IN_USE");
    expect(serverErrorKey({ code: "42501", message: "new row violates row-level security policy" })).toBe("FORBIDDEN");
    expect(serverErrorKey({ code: "23514", message: "violates check constraint" })).toBe("INVALID");
  });

  it("falls back for anything else", () => {
    expect(serverErrorKey(null)).toBe("UNKNOWN");
    expect(serverErrorKey({ message: "Failed to fetch" })).toBe("UNKNOWN");
  });
});
