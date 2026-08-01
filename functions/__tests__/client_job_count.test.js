"use strict";

const {clientsToRecount} = require("../client_job_count");

describe("clientsToRecount", () => {
  test("a create recounts the new client", () => {
    expect(clientsToRecount(null, {clientId: "c1"})).toEqual(["c1"]);
  });

  test("a delete recounts the old client", () => {
    expect(clientsToRecount({clientId: "c1"}, null)).toEqual(["c1"]);
  });

  test("a reassignment recounts both clients", () => {
    const ids = clientsToRecount({clientId: "c1"}, {clientId: "c2"});
    expect(ids.sort()).toEqual(["c1", "c2"]);
  });

  test("an unrelated edit recounts nothing", () => {
    const ids = clientsToRecount(
        {clientId: "c1", title: "Old"},
        {clientId: "c1", title: "New"},
    );
    expect(ids).toEqual([]);
  });

  test("a personal job has no clientId and recounts nothing", () => {
    const personal = {isPersonal: true, clientId: ""};
    expect(clientsToRecount(null, personal)).toEqual([]);
    expect(clientsToRecount({clientId: ""}, {clientId: ""})).toEqual([]);
  });

  test("non-string clientIds are ignored", () => {
    expect(clientsToRecount(null, {clientId: 42})).toEqual([]);
    expect(clientsToRecount(null, {})).toEqual([]);
  });

  test("blank-to-set is a reassignment from nothing", () => {
    expect(clientsToRecount({clientId: ""}, {clientId: "c2"})).toEqual(["c2"]);
  });

  test("surrounding whitespace does not fake a reassignment", () => {
    expect(clientsToRecount({clientId: " c1 "}, {clientId: "c1"})).toEqual([]);
  });
});
