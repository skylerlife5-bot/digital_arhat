import 'package:flutter/material.dart';
// Screens Imports
import 'auth/login_screen.dart';
import 'auth/phone_sign_in_screen.dart';
import 'auth/forgot_password_otp.dart';
import 'auth/signup_screen.dart';
import 'auth/otp_screen.dart';
import 'auth/face_verification_screen.dart';
import 'auth/verification_pending_screen.dart';
import 'auth/verification/liveness_detection_screen.dart';
import 'auth/set_password_screen.dart';
import 'dashboard/role_router.dart';
import 'dashboard/buyer/buyer_dashboard.dart';
import 'dashboard/seller/seller_dashboard.dart';
import 'dashboard/admin/admin_dashboard.dart';
import 'dashboard/admin/admin_payment_verification_screen.dart';
import 'dashboard/admin/listing_moderation.dart';
import 'bidding/place_bid_screen.dart'; // Bidding screen import
import 'deals/order_success_screen.dart';
import 'deals/escrow_status_screen.dart';
import 'marketplace/listing_detail_screen.dart';

class Routes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signIn = '/sign-in';
  static const String forgotPasswordOtp = '/forgot-password-otp';
  static const String signup = '/signup';
  static const String userType = '/user-type';
  static const String otp = '/otp';
  static const String roleRouter = '/role-router';
  static const String selection = '/selection';

  static const String buyerDashboard = '/buyer';
  static const String sellerDashboard = '/seller';
  static const String adminDashboard = '/admin';
  static const String adminModeration = '/admin-moderation';
  static const String adminPayments = '/admin-payments';

  static const String faceVerification = '/face';
  static const String liveness = '/liveness';
  static const String setPassword = '/set-password';
  static const String verificationPending = '/verification';
  static const String orderSuccess = '/order-success';

  // Bidding Route
  static const String placeBid = '/place_bid';
  static const String listingDetails = '/listing-details';
  static const String escrowStatus = '/escrow-status';

  static Map<String, WidgetBuilder> getRoutes() {
    return {
      login: (context) => const LoginScreen(),
      signIn: (context) => const PhoneSignInScreen(),
      forgotPasswordOtp: (context) => const ForgotPasswordOtpScreen(),

      userType: (context) => const SignUpScreen(),

      // Step 2: Detailed Profile Form
      signup: (context) => const SignUpScreen(),

      // Step 3: OTP Verification
      otp: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        String? verificationId;
        if (args is Map) {
          verificationId = args['verificationId'];
        } else if (args is String) {
          verificationId = args;
        }
        return OtpScreen(verificationId: verificationId ?? "");
      },

      // Step 4: AI Face Liveness
      liveness: (context) => const LivenessDetectionScreen(),

      // Step 5: Password / PIN Setup
      setPassword: (context) => const SetPasswordScreen(),

      // Post-Auth Routing
      roleRouter: (context) => const RoleRouter(),
      selection: (context) => const RoleRouter(),

      // BuyerDashboard Fix
      buyerDashboard: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        Map<String, dynamic> data = (args is Map<String, dynamic>) ? args : {};
        return BuyerDashboard(userData: data);
      },

      // SellerDashboard Fix
      sellerDashboard: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        Map<String, dynamic> data = (args is Map<String, dynamic>) ? args : {};
        return SellerDashboard(userData: data);
      },

      adminDashboard: (context) => const AdminDashboard(),
      adminModeration: (context) => const ListingModeration(),
      adminPayments: (context) => const AdminPaymentVerificationScreen(),

      faceVerification: (context) => const FaceVerificationScreen(),
      verificationPending: (context) => const VerificationPendingScreen(),
      orderSuccess: (context) => const OrderSuccessScreen(),

      // NEW: Bidding Screen Route with Argument Safety
      placeBid: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;

        // Agar notification se aa raha hai toh productData empty map hoga
        if (args is Map<String, dynamic>) {
          return PlaceBidScreen(
            docId: args['docId'] ?? '',
            productData: args['productData'] ?? {},
          );
        }

        // Fallback agar arguments miss ho jayein
        return const Scaffold(
          body: Center(child: Text("Data loading error...")),
        );
      },
      listingDetails: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is Map<String, dynamic>) {
          return ListingDetailScreen(
            listingId: (args['listingId'] ?? '').toString(),
            initialData: (args['data'] is Map<String, dynamic>)
                ? (args['data'] as Map<String, dynamic>)
                : const <String, dynamic>{},
          );
        }
        return const Scaffold(body: Center(child: Text('Listing not found')));
      },
      escrowStatus: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is Map<String, dynamic>) {
          return EscrowStatusScreen(
            dealId: (args['dealId'] ?? args['listingId'] ?? '').toString(),
            listingTitle: (args['title'] ?? args['listingTitle'])?.toString(),
          );
        }
        return const Scaffold(
          body: Center(child: Text('Escrow record dastiyab nahi hai')),
        );
      },
    };
  }
}

