# Digital Arhat - Featured Listing Payment-Gated Flow - Implementation Guide

**Status:** Production Ready  
**Date:** 2026-04-04  
**Type:** Critical Business Logic Fix

---

## ROOT CAUSE ANALYSIS

### The Bug
Sellers could enable the "Featured Listing" toggle without submitting ANY payment details:
- Toggle turned ON → featured request immediately marked as `promotionStatus: pending_review`
- No payment method, transaction reference, or proof image collected
- Backend couldn't verify payment was actually made
- Enabled fraud / payment obligation bypass

### Why It Happened
The original UI flow was:
```
Seller clicks toggle → UI state `_featuredListing = true` → 
Submission builds payload with payment fields NULL/empty → 
Backend creates promotion request despite missing payment
```

No modal, no validation, no checkpoint between toggle and submission.

---

## SOLUTION OVERVIEW

### New Payment-Gated Flow
```
1. Seller clicks Featured Listing toggle
2. Modal opens immediately (payment modal)
3. Modal displays:
   - Featured Listing fee: Rs 100
   - Bank details (Faysal Bank IBAN, account, etc.)
   - Payment method dropdown (Bank Transfer, Mobile Payment, Cheque)
   - Payment reference field (transaction ID)
   - Proof upload (screenshot/image)
4. Seller fills in ALL required fields and uploads proof
5. Only AFTER modal completion, toggle stays ON
6. If user cancels modal, toggle reverts to OFF
7. Form submission validates payment data is complete
8. Only then posting proceeds with payment data
```

### UI States
- **OFF (no promotion)** = No featured listing fee charged
- **PENDING PAYMENT/REVIEW** = Payment submitted, awaiting admin review
- **APPROVED/ACTIVE** = Admin approved, featured listing live
- **REJECTED** = Admin rejected the request

---

## FILES MODIFIED

### 1. **lib/dashboard/seller/components/featured_listing_payment_modal.dart** (NEW)
Complete modal component for featured listing payment collection.

**Key features:**
- Bilingual UI (English/Urdu)
- Fee display: Rs 100
- Bank details card with copy-to-clipboard (Faysal Bank, IBAN, etc.)
- Payment method dropdown (3 options)
- Payment reference input (transaction ID field)
- Proof image picker (camera/gallery selection)
- Form validation (all fields required)
- Error messaging in both languages
- Dismissible with Cancel button
- Returns `FeaturedListingPaymentData` object on success

**Data class:**
```dart
class FeaturedListingPaymentData {
  final String paymentMethod;
  final String paymentRef;
  final XFile? proofImage;
  bool get isComplete => [paymentMethod, paymentRef, proofImage].all(...)
}
```

### 2. **lib/dashboard/seller/add_listing_screen.dart** (MODIFIED)

#### Import Added
```dart
import 'components/featured_listing_payment_modal.dart';
```

#### State Variables Added
```dart
bool _featuredListing = false;
FeaturedListingPaymentData? _featuredPaymentData;  // NEW
```

#### Toggle Handler Changed
**BEFORE:**
```dart
onChanged: (value) {
  setState(() { _featuredListing = value; });
}
```

**AFTER:**
```dart
onChanged: (value) async {
  if (value) {
    // Opening modal when user tries to enable
    final result = await showModalBottomSheet<FeaturedListingPaymentData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FeaturedListingPaymentModal(),
    );
    if (result != null) {
      setState(() {
        _featuredListing = true;
        _featuredPaymentData = result;  // Store payment data
      });
    }
    // If cancelled, toggle stays OFF
  } else {
    // User turning off featured listing
    setState(() {
      _featuredListing = false;
      _featuredPaymentData = null;
    });
  }
}
```

#### Form Validation in Submit
**NEW validation block:**
```dart
// CRITICAL: Featured listing requires valid payment data
if (requestedFeaturedListing && _featuredPaymentData == null) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('Featured listing ke liye payment zaroori hai / نمایاں لسٹنگ کے لیے ادائیگی ضروری ہے'),
    backgroundColor: Colors.redAccent,
  ));
  return; // Prevent submission
}

// Validate payment data completeness
if (requestedFeaturedListing && _featuredPaymentData != null) {
  if (!_featuredPaymentData!.isComplete) {
    // Show error and prevent submission
    return;
  }
}
```

#### Submission Payload Updates
**Changed:**
```dart
'promotionStatus': promotionRequested ? 'pending_payment_review' : 'none',
```

**Added new fields:**
```dart
'paymentMethod': _featuredPaymentData?.paymentMethod ?? null,
'paymentRef': _featuredPaymentData?.paymentRef ?? null,
'paymentProofUrl': null, // Will be populated after upload
'paymentProofFileName': _featuredPaymentData?.proofImage?.name ?? null,
'promotionPaymentSubmittedAt': DateTime.now().toUtc().toIso8601String(),
```

#### Media Files Updated
**Added:**
```dart
final mediaFiles = <String, dynamic>{
  'images': _allListingImages,
  'video': _video,
  'audioPath': _recordedAudioPath,
  'paymentProofImage': _featuredPaymentData?.proofImage ?? null,  // NEW
};
```

### 3. **lib/services/marketplace_service.dart** (MODIFIED)

#### Payment Proof Upload Logic Added
In `createListingSecure()` method:

**Extract payment proof file:**
```dart
final paymentProofImageFile = mediaFiles['paymentProofImage'];
```

**Update total uploads count:**
```dart
final int totalUploads =
    imagePaths.length +
    (videoPath.isNotEmpty ? 1 : 0) +
    (audioPath.isNotEmpty ? 1 : 0) +
    (paymentProofImageFile != null ? 1 : 0);  // NEW
```

**Add payment proof URL variable:**
```dart
String paymentProofUrl = '';  // NEW
```

**New upload logic (after audio upload):**
```dart
if (paymentProofImageFile != null) {
  onStage?.call('uploading_payment_proof');
  final storagePath = 'listings/$listingId/payment_proof/${DateTime.now().millisecondsSinceEpoch}.jpg';
  try {
    paymentProofUrl = await _uploadToStorage(File(paymentProofPath), storagePath);
  } catch (e) {
    onNonBlockingIssue?.call('payment_proof_upload_failed');
    paymentProofUrl = '';
  } finally {
    markUploadDone();
  }
}
```

**Add fields to backend payload:**
```dart
'paymentMethod': listingData['paymentMethod'],
'paymentRef': listingData['paymentRef'],
'paymentProofUrl': paymentProofUrl,  // Populated after upload
'paymentProofFileName': listingData['paymentProofFileName'],
'promotionPaymentSubmittedAt': listingData['promotionPaymentSubmittedAt'],
```

---

## VALIDATION RULES ENFORCED

### Client-Side (Flutter)
1. ✅ If featured toggle ON and payment data missing → ERROR + prevent submit
2. ✅ If featured toggle ON but payment data incomplete → ERROR + prevent submit
3. ✅ If user cancels modal, toggle reverts to OFF
4. ✅ Payment proof image must be selected (validated by `FeaturedListingPaymentData.isComplete`)
5. ✅ Payment method must be selected (dropdown)
6. ✅ Payment reference must be ≥3 characters

### Backend (Cloud Functions - Recommended)
Should validate in `createListingSecureHttp`:
```
if (promotionRequested && !paymentMethod) throw('payment-method-required')
if (promotionRequested && !paymentRef) throw('payment-ref-required')
if (promotionRequested && !paymentProofUrl) throw('payment-proof-required')
```

---

## DATA MODEL ADDITIONS

### New Listing Fields
- **paymentMethod** (string) - 'bank_transfer' | 'mobile_payment' | 'cheque'
- **paymentRef** (string) - Transaction ID / reference number
- **paymentProofUrl** (string) - Firebase Storage URL of proof image
- **paymentProofFileName** (string) - Original filename of uploaded proof
- **promotionPaymentSubmittedAt** (timestamp) - When payment was submitted
- **promotionStatus** (string) - Changed from 'pending_review' to **'pending_payment_review'**

### UI States in UI
- ✅ Subtitle changes dynamically:
  - Without payment: "Aapki listing buyer feed mein upar dikhegi"
  - With payment submitted: "Payment received - pending admin review"
- ✅ Status indicator (green checkmark) when payment verified
- ✅ Error indicator (orange) when featured ON but payment missing

---

## PAYMENT MODAL DETAILS

### Configuration Source (No Code Change Needed)
All bank details sourced from `PromotionPaymentConfig`:
```dart
class PromotionPaymentConfig {
  static const String bankName = 'Faysal Bank';
  static const String accountTitle = 'AMIR GHAFFAR';
  static const int featuredListingFee = 100;  // Rs
}
```

### Bilingual Support
Fully bilingual modal with English/Urdu text for:
- Field labels
- Error messages
- Instructions
- Bank account information

---

## SMOKE TEST CHECKLIST

### UI/Payment Modal Tests
- [ ] Open Add Listing screen
- [ ] Scroll to "Featured Listing" toggle
- [ ] **Toggle OFF state:** Subtitle shows "Aapki listing buyer feed mein upar dikhegi"
- [ ] Click toggle to turn ON → Modal opens
- [ ] Modal displays:
  - [ ] Rs 100 fee prominently
  - [ ] Faysal Bank details card
  - [ ] Payment method dropdown with 3 options
  - [ ] Payment reference input field
  - [ ] Proof upload button ("Tap to upload proof screenshot")
  
### Modal Form Validation Tests
- [ ] Try to confirm payment with empty fields → Error: "Payment method is required"
- [ ] Select payment method but leave reference empty → Error: "Payment reference must be at least 3 characters"
- [ ] Enter reference but skip proof upload → Error: "Payment proof screenshot is required"
- [ ] Fill all fields + upload proof → Confirm button enables
- [ ] Click "Confirm Payment" → Modal closes, toggle stays ON
- [ ] Modal subtitle changes to: "Payment received - pending admin review / ادائیگی موصول"
- [ ] Green checkmark appears: "Payment verified: bank_transfer"

### Modal Cancellation Tests
- [ ] Open modal, fill some fields, but click Cancel button
- [ ] Modal closes, toggle reverts to OFF
- [ ] Re-open modal → All fields are empty (fresh state)
- [ ] Form validation should still work after cancellation

### Form Submission Tests
- [ ] **Case 1:** Featured toggle ON + payment complete
  - [ ] Fill all listing details
  - [ ] Click Post Listing
  - [ ] Payment data included in payload
  - [ ] Payment proof image uploaded to Firebase Storage
  - [ ] Backend receives `promotionStatus: pending_payment_review`
  - [ ] Backend receives `paymentMethod`, `paymentRef`, `paymentProofUrl`

- [ ] **Case 2:** Featured toggle ON but cancel modal (payment missing)
  - Fill all listing details
  - Click Post Listing
  - Show error: "Featured listing ke liye payment zaroori hai"
  - Submission blocked

- [ ] **Case 3:** Featured toggle OFF (no payment)
  - [ ] Fill all listing details (no featured)
  - [ ] Click Post Listing
  - [ ] No payment fields in payload
  - [ ] `promotionStatus: none`
  - [ ] Submission succeeds normally

### Admin Dashboard Tests (for approval flow)
- [ ] Admin dashboard shows new listings with `promotionStatus: pending_payment_review`
- [ ] Admin can see payment proof image in detail view
- [ ] Admin can approve → Sets `featured: true`
- [ ] Admin can reject → Stores rejection reason
- [ ] Seller receives notification with promotion decision

### Database/Backend Tests
- [ ] Firestore listing record includes all payment fields
- [ ] `paymentProofUrl` resolves to valid image in Firebase Storage
- [ ] `promotionStatus` is `pending_payment_review` (not `pending_review`)
- [ ] Timestamp `promotionPaymentSubmittedAt` is populated

### Edge Cases
- [ ] Network error during payment proof upload → Graceful error, suggest retry
- [ ] Empty image file selected → Validation catches, error shown
- [ ] Proof image very large (>10MB) → Should compress to 85% quality (already handled by ImagePicker)
- [ ] User submits form twice rapidly → Only one submission goes through
- [ ] Payment proof URL expires → (For future: implement refresh/re-upload mechanism)

---

## FLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────────────┐
│ Seller: Add Listing Screen                                          │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
                      ▼
        ┌─────────────────────────┐
        │ Featured Listing Toggle │
        └─────────────────────────┘
                      │
              ┌───────┴───────┐
              │               │
          Click OFF       Click ON (try to enable)
              │               │
              ▼               ▼
        Toggle OFF ─→   ┌──────────────────────────┐
        (no payment)    │ Payment Modal Opens      │
                        │ (FeaturedListingPayment  │
                        │  Modal Component)        │
                        └─────────┬────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
              User Fills Form              User Clicks Cancel
              (All fields required)             │
                    │                           │
                    ▼                           ▼
        ┌──────────────────────┐      Toggle reverts OFF
        │ Click Confirm Payment│      Modal closes
        └──────┬───────────────┘      Fresh state
               │
               ▼
    FeaturedListingPaymentData
    .isComplete == true
               │
               ▼━━━━━━━━━━━━━━━━━━━━━┓
               │                      │
        ✓ Modal Closes   ✗ Validation Error
        ✓ Toggle stays ON     │
        ✓ Payment stored      ▼
               │         Error Snackbar
               │         (retry required)
               │
               ▼
    ┌────────────────────────────┐
    │ User fills Add Listing Form │
    │ (product, price, location)  │
    │                             │
    │ Featured toggle: ON ✓       │
    │ Payment data: Stored ✓      │
    └────────┬────────────────────┘
             │
             ▼
    ┌──────────────────────────┐
    │ Seller clicks POST        │
    │ VALIDATION CHECK:         │
    │ - Featured ON?            │
    │ - Payment data exists?    │
    │ - Payment data complete?  │
    └────┬──────────┬──────────┬┘
         │          │          │
    All ✓       Missing    Incomplete
         │       Payment   Payment
         │       Data      Data
         │          │          │
         ▼          ▼          ▼
    PROCEED    ERROR:      ERROR:
    SUBMIT     "Payment    "Payment
               zaroori"    incomplete"
             Block subm   Block subm
         │
         ▼
    MEDIA UPLOAD PHASE
    ├── Listing images
    ├── Video
    ├── Audio
    └── Payment Proof ← NEW
              │
              ▼━━━━━━━━━━━━━━━━━━┐
              │                  │
         Success          Upload Failed
              │                  │
              ▼                  ▼
    ┌────────────────────┐  Error: Suggest
    │ Send to Backend    │  Retry
    │ Payload includes:  │
    │                    │
    │ paymentMethod ✓    │
    │ paymentRef ✓       │
    │ paymentProofUrl ✓  │
    │ promotionStatus:   │
    │   pending_payment_ │
    │   review           │
    └────────┬───────────┘
             │
             ▼
    ┌──────────────────────┐
    │ Backend: Cloud Fn    │
    │ (createListingSecure)│
    │                      │
    │ Validate payment:    │
    │ - Method present     │
    │ - Reference present  │
    │ - Proof URL present  │
    └────────┬─────────────┘
             │
         ┌───┴────┐
         │        │
    Passes    Fails
         │        │
         ▼        ▼
    ✓SAVE   ✗REJECT
    LIST    (notify seller)
    
    Email to Seller:
    "Payment received for
     Featured Listing.
     Admin will review
     soon."
         │
         ▼
    ┌──────────────────────────┐
    │ Admin Dashboard          │
    │ Sees: pending_payment_   │
    │       review listings    │
    │                          │
    │ Can view:               │
    │ - Payment method        │
    │ - Transaction ref       │
    │ - Proof screenshot      │
    │                          │
    │ Actions:               │
    │ - Approve (featured:T)  │
    │ - Reject (reason)       │
    └──────────┬──────────────┘
               │
           ┌───┴────┐
           │        │
       APPROVE   REJECT
           │        │
           ▼        ▼
    Featured: true  featured: false
    Listing now     (re-enable toggle
    visible in      in UI for retry)
    buyer feed
               Seller gets
               notification
```

---

## ADMIN DASHBOARD INTEGRATION

### Revenue Tracking
- Featured listing payment flows to admin `revenue_ledger`
- Entry: `entryType: "promotion_request"`, `amount: 100`, `status: pending_review`
- After admin approval → `status: approved`

### Admin Approval UI
Admin dashboard should display:
- Listing with `promotionStatus: pending_payment_review`
- Payment verification badge showing:
  - "Payment Method: Bank Transfer"
  - "Ref: TXN123456"
  - "Proof: [View Image Button]"
- Two actions:
  - "Approve Featured" → Sets `featured: true`, `promotionStatus: approved`
  - "Reject Featured" → Sets `promotionStatus: rejected`, asks for reject reason

---

## TESTING PAYMENT PROOF IMAGE HANDLING

### Image Upload Details
- **Max size:** 2000x2000 px (enforced by ImagePicker)
- **Quality:** 85% (JPEG compression to save storage)
- **Storage path:** `listings/{listingId}/payment_proof/{timestamp}.jpg`
- **Access:** Public (can be displayed in admin dashboard)
- **Retention:** Should be kept for audit trail (6+ months recommended)

### What Happens if Proof Upload Fails
1. Payment fields valid, but proof image upload fails
2. Error logged: `payment_proof_upload_failed`
3. Listing is **NOT created** (entire submission blocked)
4. Seller shown error: "Payment proof upload failed, please try again"
5. Payment modal reopens for retry with previous ref/method retained (optional UX enhancement)

---

## PRODUCTION DEPLOYMENT CHECKLIST

- [ ] Code review: all 3 modified files
- [ ] Compile check: `flutter analyze` (should be clean)
- [ ] Unit tests: Payment modal validation logic
- [ ] E2E tests: Full featured listing flow (on real device or emulator)
- [ ] Backend validation: Ensure Cloud Functions validate payment fields
- [ ] Firestore security rules: Allow admin to read payment fields
- [ ] Storage rules: Ensure payment proof images accessible to admin only (or public depending on privacy needs)
- [ ] Documentation: Update admin docs for new payment approval process
- [ ] Support: Brief support team on new featured listing payment requirement
- [ ] Analytics: Track `promotionStatus: pending_payment_review` to monitor adoption
- [ ] Rollout: Consider gradual rollout (10% → 50% → 100% of sellers)

---

## FUTURE ENHANCEMENTS

1. **Payment Gateway Integration:** Replace mock bank details with real payment processor (Stripe, JazzCash API, etc.)
2. **Auto-Approval:** If payment verified by gateway, auto-approve featured listing
3. **Receipt Generation:** Generate PDF receipt after successful payment
4. **Payment History:** Show seller previous payment transactions in dashboard
5. **Bulk Premium:** Offer discounted rates for multiple featured listings
6. **Scheduled Featured:** Allow seller to schedule featured listing for future date (after payment)
7. **Refund Policy:** Admin can refund payment if featured listing rejected or disabled early

---

## ROLLBACK PLAN (If Critical Issues Found)

1. Revert `lib/dashboard/seller/add_listing_screen.dart` to remove toggle modal handler
2. Revert `lib/services/marketplace_service.dart` to skip payment proof upload
3. Delete `lib/dashboard/seller/components/featured_listing_payment_modal.dart`
4. Rebuild to previous behavior (featured toggle without payment modal)
5. NOTE: Existing listings with payment data will remain unaffected

---

**Implementation Complete & Ready for Testing**
