import 'package:firebase_auth/firebase_auth.dart';
import 'user_service.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;

  static Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password.trim(),
    );
  }

  static Future<void> sendResetPassword(String email) {
    return _auth.sendPasswordResetEmail(
      email: email.trim().toLowerCase(),
    );
  }

  static Future<UserCredential> createEmployeeAccount({
    required String email,
    required String password,
  }) async {
    final invitedEmployee =
    await UserService.findInvitedEmployeeByEmail(email);

    if (invitedEmployee == null) {
      throw FirebaseAuthException(
        code: 'not-authorized',
        message: 'This email was not added by the admin.',
      );
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password.trim(),
    );

    await UserService.activateEmployee(
      docId: invitedEmployee.id,
      uid: credential.user!.uid,
    );

    return credential;
  }
}