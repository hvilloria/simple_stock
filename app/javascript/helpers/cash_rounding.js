// Round to the nearest multiple of 100; a remainder of exactly 50 rounds DOWN
// (remainder 1–50 → down, 51–99 → up). Mirrors the backend
// Payments::CashRounding.round_to_nearest_hundred (:half_down).
export function roundToNearestHundred(amount) {
  const v = amount / 100
  const floor = Math.floor(v)
  return (v - floor > 0.5 ? floor + 1 : floor) * 100
}
