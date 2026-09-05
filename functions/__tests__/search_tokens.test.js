"use strict";

// The worked examples here are shared, value for value, with
// `test/core/search/search_tokens_test.dart`. This tokenizer is hand-mirrored
// in Dart: the app writes the tokens and this side queries them, so a
// divergence is a search that silently returns nothing.

const {
  TOKEN_FIELD_LIMIT,
  TOKEN_QUERY_LIMIT,
  appointmentHistoryScopes,
  clientSearchTokens,
  normalize,
  recordMatchesQuery,
  searchIndexTokens,
  searchQueryTokens,
} = require("../search_tokens");

describe("searchQueryTokens", () => {
  test("emits one whole-word token per word plus the full digit run", () => {
    expect(searchQueryTokens("Marc 514")).toEqual(["t:marc", "t:514", "p:514"]);
  });

  test("is empty for a query with nothing searchable in it", () => {
    expect(searchQueryTokens("  --  ")).toEqual([]);
  });

  test("never sends more than the query limit", () => {
    expect(searchQueryTokens("a b c d e f g h i j k l m"))
        .toHaveLength(TOKEN_QUERY_LIMIT);
  });
});

describe("searchIndexTokens", () => {
  test("emits each whole word before any of its prefixes", () => {
    expect(searchIndexTokens({texts: ["Marc"], phones: []}))
        .toEqual(["t:marc", "t:m", "t:ma", "t:mar"]);
  });

  test("interleaves phones so a long name cannot starve them out", () => {
    // The exact list the Dart twin asserts. Before the interleave the first
    // ten were all name prefixes and the phone was never indexed at all.
    expect(searchIndexTokens({
      texts: ["Marc Tremblay"],
      phones: ["(514) 555-4321"],
      limit: 10,
    })).toEqual([
      "t:marc",
      "p:5145554321",
      "t:m",
      "p:514",
      "t:ma",
      "p:5145",
      "t:mar",
      "p:51455",
      "t:tremblay",
      "p:514555",
    ]);
  });

  test("a whole word and the whole number survive the tightest budget", () => {
    expect(searchIndexTokens({
      texts: ["Tremblay"],
      phones: ["5145554321"],
      limit: 2,
    })).toEqual(["t:tremblay", "p:5145554321"]);
  });

  test("accent folding makes an accented name reachable unaccented", () => {
    expect(searchIndexTokens({texts: ["Éric"], phones: []}))
        .toContain("t:eric");
  });

  test("a run shorter than three digits is not indexed", () => {
    expect(searchIndexTokens({texts: [], phones: ["12"]})).toEqual([]);
  });

  test("honours the field cap", () => {
    const texts = [];
    for (let i = 0; i < 200; i++) texts.push(`word${i}`);
    expect(searchIndexTokens({texts, phones: ["5145554321"]}))
        .toHaveLength(TOKEN_FIELD_LIMIT);
  });
});

describe("clientSearchTokens", () => {
  test("indexes name, an additional contact and both numbers", () => {
    const tokens = clientSearchTokens({
      name: "Plomberie Vogas",
      phone: "(514) 555-4321",
      mobile: "438 555 0000",
      contacts: [{
        name: "Sylvie",
        email: "sylvie@example.com",
        phone: "5140001111",
      }],
    });
    expect(tokens).toContain("t:plomberie");
    expect(tokens).toContain("t:sylvie");
    expect(tokens).toContain("p:5145554321");
    expect(tokens).toContain("p:4385550000");
  });
});

describe("appointmentHistoryScopes", () => {
  test("carries every token under all and each assignee scope", () => {
    const scopes = appointmentHistoryScopes({
      clientName: "Tremblay",
      clientPhone: "5145554321",
      employeeIds: ["emp1"],
      employeeNames: ["Marc"],
    });
    expect(scopes).toContain("all:t:tremblay");
    expect(scopes).toContain("emp:emp1:t:tremblay");
    expect(scopes).toContain("all:t:marc");
    // Reachable in every scope; appending it last silently lost it.
    expect(scopes).toContain("all:p:5145554321");
    expect(scopes).toContain("emp:emp1:p:5145554321");
    expect(scopes.length).toBeLessThanOrEqual(TOKEN_FIELD_LIMIT);
  });

  test("stays inside the field cap for a large crew", () => {
    const employeeIds = [];
    const employeeNames = [];
    for (let i = 0; i < 20; i++) {
      employeeIds.push(`emp${i}`);
      employeeNames.push(`Technicien${i}`);
    }
    const scopes = appointmentHistoryScopes({
      clientName: "Tremblay",
      clientPhone: "5145554321",
      employeeIds,
      employeeNames,
    });
    expect(scopes.length).toBeLessThanOrEqual(TOKEN_FIELD_LIMIT);
    expect(scopes).toContain("all:p:5145554321");
  });
});

describe("recordMatchesQuery", () => {
  test("re-verifies a token hit against the full stored text", () => {
    const client = {name: "Plomberie Vogas", phone: "5145554321"};
    expect(recordMatchesQuery(client, "vogas")).toBe(true);
    expect(recordMatchesQuery(client, "5554321")).toBe(true);
    expect(recordMatchesQuery(client, "tremblay")).toBe(false);
  });
});

describe("normalize", () => {
  // The shared worked examples; the Dart twin asserts the same four.
  test("folds the Latin-1 letters the Dart mirror folds", () => {
    expect(normalize("Muñoz")).toBe("munoz");
    expect(normalize("Éric Tremblay")).toBe("eric tremblay");
    expect(normalize("Ångström")).toBe("angstrom");
  });

  test("a letter outside the table is a separator on both sides", () => {
    expect(normalize("Šarko")).toBe("arko");
  });
});

describe("recordMatchesQuery phone seam", () => {
  const client = {
    name: "Marie Tremblay",
    phone: "5145628332",
    mobile: "4385551212",
    contacts: [{name: "Ana", phone: "5145550110"}],
  };

  it("does not match a query straddling two numbers", () => {
    // The old blob was '514562833243855512125145550110'.
    expect(recordMatchesQuery(client, "83324385")).toBe(false);
  });

  it("matches each number on its own", () => {
    expect(recordMatchesQuery(client, "5145628332")).toBe(true);
    expect(recordMatchesQuery(client, "4385551212")).toBe(true);
    expect(recordMatchesQuery(client, "5145550110")).toBe(true);
  });

  it("still matches a substring inside one number", () => {
    expect(recordMatchesQuery(client, "5628332")).toBe(true);
  });

  it("still matches text", () => {
    expect(recordMatchesQuery(client, "tremblay")).toBe(true);
  });
});
