import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/auth/data/auth_error_mapper.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';

class AccountDeletionService {
  AccountDeletionService({
    FirebaseAuth? firebaseAuth,
    FirebaseFunctions? functions,
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  Future<void> reauthenticateWithPassword(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw const AuthFailureRequiresRecentLogin();
    }
    try {
      final credential = EmailAuthProvider.credential(
        email: email.trim().toLowerCase(),
        password: password.trim(),
      );
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw AuthErrorMapper.map(e);
    }
  }

  Future<void> deleteAccount() async {
    try {
      await _functions.httpsCallable('deleteAccount').call<dynamic>();
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') {
        throw const AuthFailureRequiresRecentLogin();
      }
      throw const AuthFailureUnknown();
    } catch (_) {
      throw const AuthFailureUnknown();
    }
    await _auth.signOut();
    await AuthCache().clear();
  }
}
