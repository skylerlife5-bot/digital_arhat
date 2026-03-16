import {createHash} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";

export type GeoPointLike = {
  lat: number;
  lng: number;
};

export function normalizeProductKey(product: string): string {
  return product.trim().toLowerCase().replace(/\s+/g, "_");
}

export function hashBufferSha256(buffer: Buffer): string {
  return createHash("sha256").update(buffer).digest("hex");
}

export function haversineDistanceKm(a: GeoPointLike, b: GeoPointLike): number {
  const earthRadiusKm = 6371;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);

  const x =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(a.lat)) *
      Math.cos(toRad(b.lat)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);

  const y = 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
  return earthRadiusKm * y;
}

function toRad(value: number): number {
  return (value * Math.PI) / 180;
}

export function isWithinPakistanBounds(geo: GeoPointLike): boolean {
  const minLat = 23.5;
  const maxLat = 37.2;
  const minLng = 60.8;
  const maxLng = 77.1;
  return geo.lat >= minLat && geo.lat <= maxLat && geo.lng >= minLng && geo.lng <= maxLng;
}

export function toNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

export function toDate(value: unknown): Date | null {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (value instanceof Timestamp) return value.toDate();
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

export function uniqueStrings(values: string[]): string[] {
  return Array.from(new Set(values.filter((v) => v.trim().length > 0)));
}

export function storagePathFromUrl(url: string): string | null {
  const raw = (url || "").trim();
  if (!raw) return null;

  if (raw.startsWith("gs://")) {
    const noPrefix = raw.replace("gs://", "");
    const slashIdx = noPrefix.indexOf("/");
    if (slashIdx < 0) return null;
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
  } catch (_) {
    return null;
  }

  return null;
}

export function isSameUtcDay(a: Date, b: Date): boolean {
  return (
    a.getUTCFullYear() === b.getUTCFullYear() &&
    a.getUTCMonth() === b.getUTCMonth() &&
    a.getUTCDate() === b.getUTCDate()
  );
}
