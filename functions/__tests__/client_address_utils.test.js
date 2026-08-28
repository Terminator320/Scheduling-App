"use strict";

// Pins the street-vs-locality rule and the JS half of a hand-mirrored pair.
//
// The worked examples here are deliberately the same ones
// `test/features/maps/address_parser_street_locality_test.dart` uses, so a
// divergence between the two spellings fails a test on one side.

const {
  streetFromAddress,
  composeFullAddress,
} = require("../client_address_utils");

const MONTREAL = {
  city: "Montréal",
  province: "QC",
  postalCode: "H2X 1Y4",
  country: "Canada",
};

describe("streetFromAddress", () => {
  test("strips the locality tail the structured fields already carry", () => {
    expect(streetFromAddress(
        "1234 Rue Principale, Montréal, QC H2X 1Y4, Canada", MONTREAL))
        .toBe("1234 Rue Principale");
  });

  test("keeps a street whose own second segment is not a locality", () => {
    // Why it strips from the TAIL rather than splitting on the first comma.
    expect(streetFromAddress(
        "100 Main St, Building A, Montréal, QC H2X 1Y4, Canada", MONTREAL))
        .toBe("100 Main St, Building A");
  });

  test("is idempotent — an already-reduced street passes through", () => {
    expect(streetFromAddress("1234 Rue Principale", MONTREAL))
        .toBe("1234 Rue Principale");
  });

  test("keeps the apt prefix on the canonical stored form", () => {
    expect(streetFromAddress(
        "4-1234 Rue Principale, Montréal, QC H2X 1Y4, Canada", MONTREAL))
        .toBe("4-1234 Rue Principale");
  });

  test("matches a province and postal code joined in one segment", () => {
    expect(streetFromAddress(
        "55 Boulevard Saint-Laurent, Laval, QC H7N 1A1",
        {city: "Laval", province: "QC", postalCode: "H7N 1A1"}))
        .toBe("55 Boulevard Saint-Laurent");
  });

  test("matches regardless of case and inner spacing", () => {
    expect(streetFromAddress(
        "12 Rue Ontario,  MONTREAL , qc,  h2x   1y4",
        {city: "Montreal", province: "QC", postalCode: "H2X 1Y4"}))
        .toBe("12 Rue Ontario");
  });

  test("with no locality fields it keeps the first segment", () => {
    // A legacy doc that never had the structured fields: nothing identifies a
    // tail, so fall back rather than guess.
    expect(streetFromAddress("77 Rue Peel, Montréal, QC", {}))
        .toBe("77 Rue Peel");
  });

  test("never strips the last remaining segment", () => {
    // A street that IS the city name must not reduce to nothing.
    expect(streetFromAddress("Montréal", {city: "Montréal"}))
        .toBe("Montréal");
  });

  test("an empty address stays empty", () => {
    expect(streetFromAddress("", MONTREAL)).toBe("");
    expect(streetFromAddress(undefined, MONTREAL)).toBe("");
  });
});

describe("composeFullAddress", () => {
  test("rejoins the parts around the street", () => {
    expect(composeFullAddress({address: "1234 Rue Principale", ...MONTREAL}))
        .toBe("1234 Rue Principale, Montréal, QC H2X 1Y4, Canada");
  });

  test("BOTH stored shapes compose to the same string", () => {
    // The property the whole migration rests on: normalizing `address` to the
    // street line cannot change what anything comparing composed addresses
    // sees, so it can never fan a stripped address onto an appointment.
    const full = composeFullAddress({
      address: "1234 Rue Principale, Montréal, QC H2X 1Y4, Canada",
      ...MONTREAL,
    });
    const street = composeFullAddress({
      address: "1234 Rue Principale",
      ...MONTREAL,
    });
    expect(street).toBe(full);
  });

  test("omits parts that are missing", () => {
    expect(composeFullAddress({address: "1234 Rue Principale",
      city: "Montréal"}))
        .toBe("1234 Rue Principale, Montréal");
  });

  test("an empty address yields no leading comma", () => {
    expect(composeFullAddress({address: "", city: "Montréal", province: "QC"}))
        .toBe("Montréal, QC");
  });

  test("an empty doc composes to nothing", () => {
    expect(composeFullAddress({})).toBe("");
    expect(composeFullAddress(null)).toBe("");
  });

  test("does NOT re-spell the apt — that is the app's display concern", () => {
    // The server must never rewrite a stored appointment address into a
    // different spelling of itself; only the Dart twin renders "#4".
    expect(composeFullAddress({address: "4-1234 Rue Principale", ...MONTREAL}))
        .toBe("4-1234 Rue Principale, Montréal, QC H2X 1Y4, Canada");
  });
});
