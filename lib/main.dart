import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:scheduling/utils/themes.dart';
import 'package:scheduling/utils/theme_notifier.dart';
import 'package:splashscreen/splashscreen.dart';
import 'firebase_options.dart';

import 'views/login.dart';
import 'views/informationList.dart';

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
    return ThemeNotifier(
      themeMode: _themeMode,
      toggleTheme: toggleTheme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Themes().lightTheme,
        darkTheme: Themes().darkTheme,
        themeMode: _themeMode,
        home: const ListInformation(mode: 'Clients'),
      ),
    );
  }
}


class Splash extends StatefulWidget {
  const Splash({super.key});

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  @override
  Widget build(BuildContext context) {
    return SplashScreen(
      seconds: 5,
      navigateAfterSeconds: const Login(),
      title: Text(
        'Welcome to Scheduling App',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      styleTextUnderTheLoader: TextStyle(),
      image: Image.asset('assets/logo1.png'),
      photoSize: 170,
      loaderColor: Theme.of(context).colorScheme.secondary,
      loadingText: Text(
        'Hope you are enjoying your day!',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      loadingTextPadding: EdgeInsets.zero,
      useLoader: true,
    );
  }
}
