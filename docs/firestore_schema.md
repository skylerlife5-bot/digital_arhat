# Digital Arhat Firestore Schema

## 1) `listings` collection

Purpose: seller crop listings used by marketplace and bidding.

### Required fields (per document)
- `sellerId` (string)
- `cropType` (string)
- `price` (number)
- `quantity` (number)
- `isSuspicious` (boolean)

### Recommended fields
- `status` (string): `active | sold | archived`
- `createdAt` (timestamp)
- `updatedAt` (timestamp)

### Example document
Collection: `listings`
Document ID: auto-id or business ID

```json
{
  "sellerId": "uid_9f2a",
  "cropType": "Wheat",
  "price": 4250,
  "quantity": 120,
  "isSuspicious": false,
  "status": "active",
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp"
}
```

---

## 2) `mandi_rates` collection

Purpose: store daily average crop prices for mandi intelligence and pricing guidance.

### Required fields (per document)
- `cropType` (string) e.g., `Wheat`, `Rice`, `Corn`
- `rateDate` (timestamp; normalized to date only)
- `averagePrice` (number)

### Recommended fields
- `unit` (string): e.g., `PKR/40kg`
- `source` (string): e.g., `daily_aggregation`
- `createdAt` (timestamp)
- `updatedAt` (timestamp)

### Example documents
Collection: `mandi_rates`
Document IDs (recommended): `wheat_2026-02-23`, `rice_2026-02-23`, `corn_2026-02-23`

```json
{
  "cropType": "Wheat",
  "rateDate": "2026-02-23T00:00:00Z",
  "averagePrice": 4300,
  "unit": "PKR/40kg",
  "source": "daily_aggregation",
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp"
}
```

```json
{
  "cropType": "Rice",
  "rateDate": "2026-02-23T00:00:00Z",
  "averagePrice": 6900,
  "unit": "PKR/40kg",
  "source": "daily_aggregation",
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp"
}
```

```json
{
  "cropType": "Corn",
  "rateDate": "2026-02-23T00:00:00Z",
  "averagePrice": 3150,
  "unit": "PKR/40kg",
  "source": "daily_aggregation",
  "createdAt": "serverTimestamp",
  "updatedAt": "serverTimestamp"
}
```

---

## 3) Index recommendations

### `listings`
- Composite: `(sellerId ASC, createdAt DESC)`
- Composite: `(cropType ASC, createdAt DESC)`
- Composite: `(isSuspicious ASC, createdAt DESC)`

### `mandi_rates`
- Composite: `(cropType ASC, rateDate DESC)`
- Optional uniqueness strategy: use deterministic document ID `<cropType>_<yyyy-mm-dd>`.

---

## 4) Operational guidance

- Always write `createdAt` and `updatedAt` with server timestamps.
- Keep `cropType` values canonical (`Wheat`, `Rice`, `Corn`) to avoid duplicate analytics buckets.
- Treat `isSuspicious = true` listings as moderation queue candidates.
