import 'package:flutter/material.dart';

import 'auth/auth_wrapper.dart';
import 'auth/create_account_screen.dart';
import 'auth/face_verification_screen.dart';
import 'auth/forgot_password_otp.dart';
import 'auth/login_screen.dart';
import 'auth/master_sign_up_screen.dart';
import 'auth/otp_screen.dart';
import 'auth/set_password_screen.dart';
import 'auth/verification/liveness_detection_screen.dart';
import 'auth/verification_pending_screen.dart';
import 'bidding/place_bid_screen.dart';
import 'dashboard/admin/admin_completion_reports_screen.dart';
import 'dashboard/admin/admin_dashboard.dart';
import 'dashboard/admin/listing_moderation.dart';
import 'dashboard/buyer/buyer_dashboard.dart';
import 'dashboard/buyer/buyer_listing_detail_screen.dart';
import 'dashboard/seasonal/bakra_mandi_entry_screen.dart';
import 'dashboard/seasonal/bakra_mandi_list_screen.dart';
import 'dashboard/seasonal/bakra_mandi_post_screen.dart';
import 'dashboard/seasonal/post_listing_option_screen.dart';
import 'dashboard/role_router.dart';
import 'dashboard/seller/seller_dashboard.dart';
import 'dashboard/seller/add_listing_screen.dart';
import 'deals/order_success_screen.dart';
import 'splash/splash_screen.dart';

class Routes {
  static const String splash = '/splash';
  static const String welcome = '/welcome';
  static const String authWrapper = '/authWrapper';
  static const String createAccount = '/createAccount';
  static const String masterSignUp = '/masterSignUp';
  static const String buyerAuth = '/buyerAuth';
  static const String sellerAuth = '/sellerAuth';
  static const String buyerDashboard = '/buyerDashboard';
  static const String sellerDashboard = '/sellerDashboard';
  static const String sellerAddListing = '/seller-add-listing';
  static const String postListingOption = '/post-listing-option';
  static const String bakraMandiEntry = '/bakra-mandi-entry';
  static const String bakraMandiList = '/bakra-mandi-list';
  static const String bakraMandiPost = '/bakra-mandi-post';

  static const String roleRouter = '/role-router';
  static const String adminDashboard = '/admin';
  static const String adminModeration = '/admin-moderation';
  static const String adminPayments = '/admin-payments';
  static const String adminCompletionReports = '/admin-completion-reports';

  static const String forgotPasswordOtp = '/forgot-password-otp';
  static const String otp = '/otp';
  static const String faceVerification = '/face';
  static const String liveness = '/liveness';
  static const String setPassword = '/set-password';
  static const String verificationPending = '/verification';
  static const String orderSuccess = '/order-success';

  static const String placeBid = '/place_bid';
  static const String listingDetails = '/listing-details';
  static const String escrowStatus = '/escrow-status';

  static const String signup = '/signup';
  static const String userType = '/userType';
  static const String login = '/login';
  static const String home = '/home';
  static const String selection = '/selection';

  static Map<String, WidgetBuilder> getRoutes() {
    return {
      splash: (context) => const AuthWrapper(),
      welcome: (context) => const WelcomeScreen(),
      createAccount: (context) => const CreateAccountScreen(),
      masterSignUp: (context) => const MasterSignUpScreen(),
      login: (context) => const LoginScreen(),

      buyerDashboard: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        final data = (args is Map<String, dynamic>) ? args : <String, dynamic>{};
        return BuyerDashboard(userData: data);
      },
      sellerDashboard: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        final data = (args is Map<String, dynamic>) ? args : <String, dynamic>{};
        return SellerDashboard(userData: data);
      },
      sellerAddListing: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        final data = (args is Map<String, dynamic>) ? (args['userData'] as Map<String, dynamic>? ?? args) : <String, dynamic>{};
        return AddListingScreen(userData: data);
      },
      postListingOption: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        final data = (args is Map<String, dynamic>) ? (args['userData'] as Map<String, dynamic>? ?? args) : <String, dynamic>{};
        return PostListingOptionScreen(userData: data);
      },
      bakraMandiEntry: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        final data = (args is Map<String, dynamic>) ? args : <String, dynamic>{};
        return BakraMandiEntryScreen(initialAnimalType: data['animalType']?.toString());
      },
      bakraMandiList: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        final data = (args is Map<String, dynamic>) ? args : <String, dynamic>{};
        return BakraMandiListScreen(
          initialAnimalType: data['animalType']?.toString(),
          initialQuery: data['query']?.toString(),
        );
      },
      bakraMandiPost: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        final data = (args is Map<String, dynamic>) ? (args['userData'] as Map<String, dynamic>? ?? args) : <String, dynamic>{};
        return BakraMandiPostScreen(userData: data);
      },

      authWrapper: (context) => const AuthWrapper(),
      roleRouter: (context) => const RoleRouter(),
      home: (context) => const WelcomeScreen(),

      adminDashboard: (context) => const AdminDashboard(),
      adminModeration: (context) => const ListingModeration(),
      adminCompletionReports: (context) =>
          const AdminCompletionReportsScreen(),
      adminPayments: (context) => const Scaffold(
        body: Center(
          child: Text('Phase-2 payment verification is disabled in Phase-1.'),
        ),
      ),

      forgotPasswordOtp: (context) => const ForgotPasswordOtpScreen(),
      otp: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        String? verificationId;
        if (args is Map) {
          verificationId = args['verificationId'];
        } else if (args is String) {
          verificationId = args;
        }
        return OtpScreen(verificationId: verificationId ?? '');
      },
      liveness: (context) => const LivenessDetectionScreen(),
      setPassword: (context) => const SetPasswordScreen(),
      faceVerification: (context) => const FaceVerificationScreen(),
      verificationPending: (context) => const VerificationPendingScreen(),
      orderSuccess: (context) => const OrderSuccessScreen(),

      placeBid: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is Map<String, dynamic>) {
          return PlaceBidScreen(
            docId: args['docId'] ?? '',
            productData: args['productData'] ?? {},
          );
        }
        return const Scaffold(body: Center(child: Text('Data loading error...')));
      },
      listingDetails: (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is Map<String, dynamic>) {
          return BuyerListingDetailScreen(
            listingId: (args['listingId'] ?? '').toString(),
            initialData: (args['data'] is Map<String, dynamic>)
                ? (args['data'] as Map<String, dynamic>)
                : null,
          );
        }
        return const Scaffold(body: Center(child: Text('Listing not found')));
      },
      escrowStatus: (context) {
        return const Scaffold(
          body: Center(
            child: Text('Escrow flow is disabled in Phase-1.'),
          ),
        );
      },

    };
  }
}
