"use strict";

/**
 * @fileoverview The i18n (EN/FR) message table for push notifications plus the
 * pure `build*Message` helpers that consume it. Split out of
 * `notification_utils.js` to keep that module focused on the diff/ledger/send
 * pipeline. Depends only on `time_utils` for locale-aware time formatting, so
 * it closes no require cycle (nothing here requires back into
 * `notification_utils`).
 *
 * @module notification_messages
 */

const {
  toMillis,
  formatBusinessTime,
  formatTimeOfDay,
} = require("./time_utils");

/**
 * Localized "Wed, Jul 8, 2:00 p.m." style datetime.
 * @param {string} locale
 * @param {*} startTime
 * @return {string}
 */
function _dateTime(locale, startTime) {
  return formatBusinessTime(locale, startTime, {
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

/**
 * Localized time only.
 * @param {string} locale
 * @param {*} startTime
 * @return {string}
 */
function _timeOnly(locale, startTime) {
  return formatTimeOfDay(locale, startTime);
}

/**
 * Localized recurrence phrase ("every 6 months"/"aux 6 mois") for a
 * RepeatInterval raw value, mirroring RepeatInterval.raw
 * (repeat_interval.dart). Returns "" for none/unknown, so a one-off job
 * reads as a plain assignment.
 * @param {string} raw
 * @param {string} locale 'en' | 'fr'.
 * @return {string}
 */
function _repeatLabel(raw, locale) {
  const fr = locale === "fr";
  switch (String(raw || "").toLowerCase()) {
    case "four_months": return fr ? "aux 4 mois" : "every 4 months";
    case "six_months": return fr ? "aux 6 mois" : "every 6 months";
    case "one_year": return fr ? "chaque année" : "every year";
    default: return "";
  }
}

const _MESSAGES = {
  en: {
    who: (c) => (c.clientName || "").trim() || "Client",
    assigned: (c, who) => {
      const repeat = _repeatLabel(c.repeat, "en");
      return repeat ? {
        title: "New repeating job assigned",
        body: `${who} · ${_dateTime("en", c.startTime)} · repeats ${repeat}`,
      } : {
        title: "New job assigned",
        body: `${who} · ${_dateTime("en", c.startTime)}`,
      };
    },
    rescheduled: (c, who) => ({
      title: "Job rescheduled",
      body: `${who} · now ${_dateTime("en", c.startTime)}`,
    }),
    cancelled: (c, who) => ({
      title: "Job cancelled",
      body: `${who} · ${_dateTime("en", c.startTime)}`,
    }),
    removed: (c, who) => ({
      title: "Removed from a job",
      body: `${who} · ${_dateTime("en", c.startTime)}`,
    }),
    reminder: (c, who) => {
      const addr = (c.address || "").trim();
      const base = `${who} at ${_timeOnly("en", c.startTime)}`;
      return {
        title: "Upcoming job",
        body: addr ? `${base} · ${addr}` : base,
      };
    },
    leaveNow: (c, who) => {
      const addr = (c.address || "").trim();
      const drive = `About ${c.travelMinutes} min drive`;
      return {
        title: `Time to leave — ${who} at ${_timeOnly("en", c.startTime)}`,
        body: addr ? `${drive} · ${addr}` : drive,
      };
    },
    doneCheck: (c, who) => ({
      title: "Job finished?",
      body: `Is the job for ${who} done yet? Open the app to update its ` +
          "status.",
    }),
  },
  fr: {
    who: (c) => (c.clientName || "").trim() || "un client",
    assigned: (c, who) => {
      const repeat = _repeatLabel(c.repeat, "fr");
      return repeat ? {
        title: "Nouvelle visite récurrente",
        body: `${who} · ${_dateTime("fr", c.startTime)} · se répète ${repeat}`,
      } : {
        title: "Nouvelle visite assignée",
        body: `${who} · ${_dateTime("fr", c.startTime)}`,
      };
    },
    rescheduled: (c, who) => ({
      title: "Visite reportée",
      body: `${who} · maintenant ${_dateTime("fr", c.startTime)}`,
    }),
    cancelled: (c, who) => ({
      title: "Visite annulée",
      body: `${who} · ${_dateTime("fr", c.startTime)}`,
    }),
    removed: (c, who) => ({
      title: "Retiré d'une visite",
      body: `${who} · ${_dateTime("fr", c.startTime)}`,
    }),
    reminder: (c, who) => {
      const addr = (c.address || "").trim();
      const base = `${who} à ${_timeOnly("fr", c.startTime)}`;
      return {
        title: "Visite à venir",
        body: addr ? `${base} · ${addr}` : base,
      };
    },
    leaveNow: (c, who) => {
      const addr = (c.address || "").trim();
      const drive = `Environ ${c.travelMinutes} min de route`;
      return {
        title: `C'est l'heure de partir — ${who} à ` +
            `${_timeOnly("fr", c.startTime)}`,
        body: addr ? `${drive} · ${addr}` : drive,
      };
    },
    doneCheck: (c, who) => ({
      title: "Travail terminé ?",
      body: `Le travail pour ${who} est-il terminé ? ` +
          "Ouvrez l'application pour mettre à jour son statut.",
    }),
  },
};

/**
 * Builds a localized {title, body} for a per-appointment notification.
 * Pure — unit-testable.
 * @param {string} kind
 *   assigned|rescheduled|cancelled|removed|reminder|doneCheck.
 * @param {{clientName: string, startTime: *, address: string}} ctx
 * @param {string} locale 'en' | 'fr'.
 * @return {{title: string, body: string}}
 */
function buildNotificationMessage(kind, ctx, locale) {
  const table = _MESSAGES[locale === "fr" ? "fr" : "en"];
  const build = table[kind];
  if (!build) return {title: "", body: ""};
  const c = ctx || {};
  return build(c, table.who(c));
}

/**
 * Builds the nightly-digest {title, body}. Pure — unit-testable.
 * @param {!Array<!Object>} jobs Tomorrow's jobs for one employee.
 * @param {string} locale 'en' | 'fr'.
 * @return {{title: string, body: string}}
 */
function buildDigestMessage(jobs, locale) {
  const fr = locale === "fr";
  const sorted = [...(jobs || [])].sort(
      (a, b) => (toMillis(a.startTime) || 0) - (toMillis(b.startTime) || 0),
  );
  const n = sorted.length;
  const first = sorted[0];
  const who = first ?
    ((first.clientName || "").trim() || (fr ? "un client" : "Client")) :
    "";
  const time = first ? _timeOnly(fr ? "fr" : "en", first.startTime) : "";
  if (fr) {
    const noun = n === 1 ? "visite" : "visites";
    return {
      title: "Votre horaire de demain",
      body: first ?
        `Vous avez ${n} ${noun} demain. Première : ${who} à ${time}.` :
        "Vous avez des visites demain.",
    };
  }
  const noun = n === 1 ? "job" : "jobs";
  return {
    title: "Tomorrow's schedule",
    body: first ?
      `You have ${n} ${noun} tomorrow. First: ${who} at ${time}.` :
      "You have jobs tomorrow.",
  };
}

module.exports = {
  buildNotificationMessage,
  buildDigestMessage,
};
