"use strict";

const {classifyWaveError} = require("../wave/errors");
const {WaveApiError} = require("../wave/client");
const {WaveValidationError} = require("../wave/customers");

describe("classifyWaveError", () => {
  test("WaveApiError(auth) → failed-precondition / wave/token-invalid", () => {
    const out = classifyWaveError(new WaveApiError("auth", "revoked"));
    expect(out).toEqual({
      code: "failed-precondition",
      message: "wave/token-invalid",
    });
  });

  test("WaveApiError(rateLimited) → resource-exhausted / wave/rate-limited",
      () => {
        const out = classifyWaveError(
            new WaveApiError("rateLimited", "429"),
        );
        expect(out).toEqual({
          code: "resource-exhausted",
          message: "wave/rate-limited",
        });
      });

  test("WaveApiError(network) → unavailable / wave/network", () => {
    const out = classifyWaveError(new WaveApiError("network", "timeout"));
    expect(out).toEqual({code: "unavailable", message: "wave/network"});
  });

  test("WaveApiError(graphql) → invalid-argument / wave/validation", () => {
    const out = classifyWaveError(new WaveApiError("graphql", "resolver"));
    expect(out).toEqual({
      code: "invalid-argument",
      message: "wave/validation",
    });
  });

  test("WaveValidationError → invalid-argument / wave/validation", () => {
    const out = classifyWaveError(
        new WaveValidationError([{code: "INVALID_EMAIL"}]),
    );
    expect(out).toEqual({
      code: "invalid-argument",
      message: "wave/validation",
    });
  });

  test("WaveApiError(unknown) → internal / wave/unknown", () => {
    const out = classifyWaveError(new WaveApiError("unknown", "weird"));
    expect(out).toEqual({code: "internal", message: "wave/unknown"});
  });

  test("a plain Error → internal / wave/unknown", () => {
    const out = classifyWaveError(new Error("boom"));
    expect(out).toEqual({code: "internal", message: "wave/unknown"});
  });

  test("a non-error value → internal / wave/unknown", () => {
    expect(classifyWaveError(null)).toEqual({
      code: "internal",
      message: "wave/unknown",
    });
    expect(classifyWaveError("nope")).toEqual({
      code: "internal",
      message: "wave/unknown",
    });
  });

  test("never echoes the raw Wave error message", () => {
    const out = classifyWaveError(
        new WaveApiError("auth", "Token for jane.doe@example.com expired"),
    );
    expect(JSON.stringify(out)).not.toContain("jane.doe@example.com");
    expect(JSON.stringify(out)).not.toContain("expired");
  });
});
