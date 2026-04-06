import 'package:firebase_auth/firebase_auth.dart';
import 'user_service.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password.trim(),
    );
  }

   Future<void> sendResetPassword(String email) {
    return _auth.sendPasswordResetEmail(
      email: email.trim().toLowerCase(),
    );
  }

   Future<UserCredential> createEmployeeAccount({
    required String email,
    required String password,
  }) async {
    final userService = UserService();

    final invitedEmployee =
    await userService.findInvitedEmployeeByEmail(email);

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

    await userService.activateEmployee(
      docId: invitedEmployee.id,
      uid: credential.user!.uid,
    );

    return credential;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Stream<User?> get authStateChanges => _auth.authStateChanges();


}