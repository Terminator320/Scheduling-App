"use strict";

/**
 * @fileoverview What a job is CALLED, wherever it is spoken to a person.
 * @module job_naming
 */

/**
 * Who a card or push names the job after: the client, or a personal job's
 * title.
 * @param {!Object} c Anything carrying `clientName` / `title`.
 * @param {string} generic Localized "Client" placeholder.
 * @return {string}
 */
function whoFor(c, generic) {
  return (c.clientName || "").trim() || (c.title || "").trim() || generic;
}

module.exports = {whoFor};
