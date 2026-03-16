import {UnifiedMandiRate} from "./types";

export type HumanCorroborationInput = {
  candidatePrice: number;
  city: string;
  mandiName: string;
  unit: string;
  categoryName: string;
  subCategoryName: string;
  officialComparable: UnifiedMandiRate[];
  trustedHumanComparable: UnifiedMandiRate[];
};

export type HumanCorroborationResult = {
  corroborationCount: number;
  officialAgreement: number;
  trustedContributorAgreement: number;
  sameCityMandiAlignment: boolean;
  stableTaxonomyAlignment: boolean;
  weakCorroboration: boolean;
  suspiciousDeviation: boolean;
  reason: string;
};

function normalizedDeviation(a: number, b: number): number {
  if (a <= 0 || b <= 0) return 1;
  return Math.abs(a - b) / Math.max(a, b);
}

function average(values: number[]): number {
  if (values.length == 0) return 0;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function agreementFromComparable(price: number, comparable: UnifiedMandiRate[]): number {
  const valid = comparable.map((item) => item.price).filter((value) => value > 0);
  if (valid.length == 0) return 0;
  const avg = average(valid);
  const deviation = normalizedDeviation(price, avg);
  return Math.max(0, 1 - Math.min(1, deviation));
}

export function assessHumanCorroboration(input: HumanCorroborationInput): HumanCorroborationResult {
  const officialAgreement = Number(
    agreementFromComparable(input.candidatePrice, input.officialComparable).toFixed(3),
  );
  const trustedContributorAgreement = Number(
    agreementFromComparable(input.candidatePrice, input.trustedHumanComparable).toFixed(3),
  );

  const sameCityMandiAlignment = [...input.officialComparable, ...input.trustedHumanComparable].some((item) => {
    const cityOk = item.city.trim().toLowerCase() == input.city.trim().toLowerCase();
    const mandiOk = item.mandiName.trim().toLowerCase() == input.mandiName.trim().toLowerCase();
    return cityOk || mandiOk;
  });

  const stableTaxonomyAlignment = [...input.officialComparable, ...input.trustedHumanComparable].some((item) => {
    return item.unit.trim().toLowerCase() == input.unit.trim().toLowerCase() &&
      item.categoryName.trim().toLowerCase() == input.categoryName.trim().toLowerCase() &&
      item.subCategoryName.trim().toLowerCase() == input.subCategoryName.trim().toLowerCase();
  });

  const corroborationCount = input.officialComparable.length + input.trustedHumanComparable.length;
  const weakCorroboration = corroborationCount < 2 ||
    (officialAgreement < 0.45 && trustedContributorAgreement < 0.5);
  const suspiciousDeviation = officialAgreement < 0.3 && trustedContributorAgreement < 0.3;

  return {
    corroborationCount,
    officialAgreement,
    trustedContributorAgreement,
    sameCityMandiAlignment,
    stableTaxonomyAlignment,
    weakCorroboration,
    suspiciousDeviation,
    reason: [
      `officialAgreement=${officialAgreement.toFixed(3)}`,
      `trustedAgreement=${trustedContributorAgreement.toFixed(3)}`,
      `corroborationCount=${corroborationCount}`,
      `sameCityMandi=${sameCityMandiAlignment ? "yes" : "no"}`,
      `taxonomyStable=${stableTaxonomyAlignment ? "yes" : "no"}`,
      `weak=${weakCorroboration ? "yes" : "no"}`,
      `suspiciousDeviation=${suspiciousDeviation ? "yes" : "no"}`,
    ].join(";"),
  };
}
