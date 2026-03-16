import {SourceFamily} from "./types";

export type TopPriorityMandiTarget = {
  city: string;
  district: string;
  province: string;
  aliases: string[];
  priorityRank: number;
  expectedSourceFamily: SourceFamily;
  latitude: number | null;
  longitude: number | null;
  enabled: boolean;
  futureReady: boolean;
};

const SOURCE_BY_CITY: Record<string, SourceFamily> = {
  Lahore: "official_city_market_source",
  Karachi: "official_commissioner_source",
  Hyderabad: "official_commissioner_source",
};

const CITY_COORDS: Record<string, {lat: number; lng: number}> = {
  Lahore: {lat: 31.5204, lng: 74.3587},
  Faisalabad: {lat: 31.4504, lng: 73.135},
  Rawalpindi: {lat: 33.5651, lng: 73.0169},
  Multan: {lat: 30.1575, lng: 71.5249},
  Bahawalpur: {lat: 29.3956, lng: 71.6836},
  Gujranwala: {lat: 32.1877, lng: 74.1945},
  Sargodha: {lat: 32.0836, lng: 72.6711},
  Gujrat: {lat: 32.5711, lng: 74.075},
  "D.G. Khan": {lat: 30.0452, lng: 70.6402},
  Sahiwal: {lat: 30.6706, lng: 73.1069},
  Okara: {lat: 30.8103, lng: 73.4516},
  Vehari: {lat: 30.0445, lng: 72.3556},
  "Rahim Yar Khan": {lat: 28.4212, lng: 70.2989},
  Bhakkar: {lat: 31.6269, lng: 71.0654},
  Layyah: {lat: 30.9693, lng: 70.9428},
  Khanewal: {lat: 30.3004, lng: 71.932},
  Muzaffargarh: {lat: 30.0726, lng: 71.1938},
  "Toba Tek Singh": {lat: 30.9744, lng: 72.4829},
  Kabirwala: {lat: 30.4055, lng: 71.8657},
  Lodhran: {lat: 29.5339, lng: 71.6324},
  Chichawatni: {lat: 30.5301, lng: 72.6916},
  Jhelum: {lat: 32.9405, lng: 73.7276},
  Mianwali: {lat: 32.5862, lng: 71.5436},
  Karachi: {lat: 24.8607, lng: 67.0011},
  Hyderabad: {lat: 25.396, lng: 68.3578},
};

function familyForCity(city: string): SourceFamily {
  return SOURCE_BY_CITY[city] ?? "future_city_committee_source";
}

function aliasesForCity(city: string): string[] {
  const lower = city.toLowerCase();
  const aliases = new Set<string>([city, lower]);

  if (city === "Lahore") aliases.add("لاہور");
  if (city === "Faisalabad") aliases.add("فیصل آباد");
  if (city === "Rawalpindi") aliases.add("راولپنڈی");
  if (city === "Multan") aliases.add("ملتان");
  if (city === "Bahawalpur") aliases.add("بہاولپور");
  if (city === "Gujranwala") aliases.add("گوجرانوالہ");
  if (city === "Sargodha") aliases.add("سرگودھا");
  if (city === "Gujrat") aliases.add("گجرات");
  if (city === "D.G. Khan") {
    aliases.add("DG Khan");
    aliases.add("Dera Ghazi Khan");
    aliases.add("ڈیرہ غازی خان");
  }
  if (city === "Sahiwal") aliases.add("ساہیوال");
  if (city === "Okara") aliases.add("اوکاڑہ");
  if (city === "Vehari") aliases.add("وہاڑی");
  if (city === "Rahim Yar Khan") aliases.add("رحیم یار خان");
  if (city === "Bhakkar") aliases.add("بھکر");
  if (city === "Layyah") aliases.add("لیہ");
  if (city === "Khanewal") aliases.add("خانیوال");
  if (city === "Muzaffargarh") aliases.add("مظفرگڑھ");
  if (city === "Toba Tek Singh") aliases.add("ٹوبہ ٹیک سنگھ");
  if (city === "Kabirwala") aliases.add("کبیروالا");
  if (city === "Lodhran") aliases.add("لودھراں");
  if (city === "Chichawatni") aliases.add("چیچہ وطنی");
  if (city === "Jhelum") aliases.add("جہلم");
  if (city === "Mianwali") aliases.add("میانوالی");
  if (city === "Karachi") aliases.add("کراچی");
  if (city === "Hyderabad") aliases.add("حیدرآباد");

  return Array.from(aliases);
}

const PRIORITY_ORDER = [
  ["Lahore", "Lahore", "Punjab"],
  ["Faisalabad", "Faisalabad", "Punjab"],
  ["Rawalpindi", "Rawalpindi", "Punjab"],
  ["Multan", "Multan", "Punjab"],
  ["Bahawalpur", "Bahawalpur", "Punjab"],
  ["Gujranwala", "Gujranwala", "Punjab"],
  ["Sargodha", "Sargodha", "Punjab"],
  ["Gujrat", "Gujrat", "Punjab"],
  ["D.G. Khan", "Dera Ghazi Khan", "Punjab"],
  ["Sahiwal", "Sahiwal", "Punjab"],
  ["Okara", "Okara", "Punjab"],
  ["Vehari", "Vehari", "Punjab"],
  ["Rahim Yar Khan", "Rahim Yar Khan", "Punjab"],
  ["Bhakkar", "Bhakkar", "Punjab"],
  ["Layyah", "Layyah", "Punjab"],
  ["Khanewal", "Khanewal", "Punjab"],
  ["Muzaffargarh", "Muzaffargarh", "Punjab"],
  ["Toba Tek Singh", "Toba Tek Singh", "Punjab"],
  ["Kabirwala", "Khanewal", "Punjab"],
  ["Lodhran", "Lodhran", "Punjab"],
  ["Chichawatni", "Sahiwal", "Punjab"],
  ["Jhelum", "Jhelum", "Punjab"],
  ["Mianwali", "Mianwali", "Punjab"],
  ["Karachi", "Karachi", "Sindh"],
  ["Hyderabad", "Hyderabad", "Sindh"],
] as const;

export const TOP_25_MANDI_TARGETS: TopPriorityMandiTarget[] = PRIORITY_ORDER.map((entry, index) => {
  const city = entry[0];
  const district = entry[1];
  const province = entry[2];
  const coords = CITY_COORDS[city] ?? null;
  const family = familyForCity(city);
  return {
    city,
    district,
    province,
    aliases: aliasesForCity(city),
    priorityRank: index + 1,
    expectedSourceFamily: family,
    latitude: coords?.lat ?? null,
    longitude: coords?.lng ?? null,
    enabled: true,
    futureReady: family.startsWith("future_"),
  };
});

export function getEnabledTopPriorityMandis(): TopPriorityMandiTarget[] {
  return TOP_25_MANDI_TARGETS.filter((item) => item.enabled);
}
