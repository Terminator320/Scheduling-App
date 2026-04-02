import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:scheduling/utils/themes.dart';
import 'package:splashscreen/splashscreen.dart';
import 'firebase_options.dart';

import 'views/login.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: "dev/.env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.android,
  );

  runApp(PaulApp());
}

class PaulApp extends StatefulWidget {
  const PaulApp({super.key});

  @override
  State<PaulApp> createState() => _PaulAppState();
}

class _PaulAppState extends State<PaulApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Themes().lightTheme,
      darkTheme: Themes().darkTheme,
      themeMode: _themeMode,
      home: Splash(toggleTheme: toggleTheme),
    );
  }
}


class Splash extends StatefulWidget {
  final VoidCallback toggleTheme;

  const Splash({super.key, required this.toggleTheme});

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  @override
  Widget build(BuildContext context) {
    return SplashScreen(
      seconds: 10,
      navigateAfterSeconds: Login(),
      title: Text(
        'Welcome to my Product',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      styleTextUnderTheLoader: TextStyle(),
      image: Image.asset('assets/george.JPG'),
      photoSize: 150,
      loaderColor: Theme.of(context).colorScheme.primary,
      loadingText: Text(
        'Hey Welcome ',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      loadingTextPadding: EdgeInsets.zero,
      useLoader: true,
    );
  }
}
