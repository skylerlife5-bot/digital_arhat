"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeProductKey = normalizeProductKey;
exports.hashBufferSha256 = hashBufferSha256;
exports.haversineDistanceKm = haversineDistanceKm;
exports.isWithinPakistanBounds = isWithinPakistanBounds;
exports.toNumber = toNumber;
exports.toDate = toDate;
exports.uniqueStrings = uniqueStrings;
exports.storagePathFromUrl = storagePathFromUrl;
exports.isSameUtcDay = isSameUtcDay;
const node_crypto_1 = require("node:crypto");
const firestore_1 = require("firebase-admin/firestore");
function normalizeProductKey(product) {
    return product.trim().toLowerCase().replace(/\s+/g, "_");
}
function hashBufferSha256(buffer) {
    return (0, node_crypto_1.createHash)("sha256").update(buffer).digest("hex");
}
function haversineDistanceKm(a, b) {
    const earthRadiusKm = 6371;
    const dLat = toRad(b.lat - a.lat);
    const dLng = toRad(b.lng - a.lng);
    const x = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(toRad(a.lat)) *
            Math.cos(toRad(b.lat)) *
            Math.sin(dLng / 2) *
            Math.sin(dLng / 2);
    const y = 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
    return earthRadiusKm * y;
}
function toRad(value) {
    return (value * Math.PI) / 180;
}
function isWithinPakistanBounds(geo) {
    const minLat = 23.5;
    const maxLat = 37.2;
    const minLng = 60.8;
    const maxLng = 77.1;
    return geo.lat >= minLat && geo.lat <= maxLat && geo.lng >= minLng && geo.lng <= maxLng;
}
function toNumber(value, fallback = 0) {
    if (typeof value === "number" && Number.isFinite(value))
        return value;
    if (typeof value === "string") {
        const parsed = Number(value);
        if (Number.isFinite(parsed))
            return parsed;
    }
    return fallback;
}
function toDate(value) {
    if (!value)
        return null;
    if (value instanceof Date)
        return value;
    if (value instanceof firestore_1.Timestamp)
        return value.toDate();
    if (typeof value === "string") {
        const parsed = new Date(value);
        return Number.isNaN(parsed.getTime()) ? null : parsed;
    }
    return null;
}
function uniqueStrings(values) {
    return Array.from(new Set(values.filter((v) => v.trim().length > 0)));
}
function storagePathFromUrl(url) {
    const raw = (url || "").trim();
    if (!raw)
        return null;
    if (raw.startsWith("gs://")) {
        const noPrefix = raw.replace("gs://", "");
        const slashIdx = noPrefix.indexOf("/");
        if (slashIdx < 0)
            return null;
        return noPrefix.slice(slashIdx + 1);
    }
    try {
        const parsed = new URL(raw);
        const marker = "/o/";
        const idx = parsed.pathname.indexOf(marker);
        if (idx >= 0) {
            const encodedPath = parsed.pathname.slice(idx + marker.length);
            return decodeURIComponent(encodedPath);
        }
    }
    catch (_) {
        return null;
    }
    return null;
}
function isSameUtcDay(a, b) {
    return (a.getUTCFullYear() === b.getUTCFullYear() &&
        a.getUTCMonth() === b.getUTCMonth() &&
        a.getUTCDate() === b.getUTCDate());
}
