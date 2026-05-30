import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';

void main() {
  enableFlutterDriverExtension();
  runApp(const _RainAppiumSmokeApp());
}

class _RainAppiumSmokeApp extends StatefulWidget {
  const _RainAppiumSmokeApp();

  @override
  State<_RainAppiumSmokeApp> createState() => _RainAppiumSmokeAppState();
}

class _RainAppiumSmokeAppState extends State<_RainAppiumSmokeApp> {
  var _createAccountMode = false;

  @override
  Widget build(BuildContext context) {
    final title = _createAccountMode ? 'Create account' : 'Sign in';
    final toggleText = _createAccountMode ? 'Sign in' : 'Create account';
    final titleSemantics = _createAccountMode
        ? 'Create account mode'
        : 'Sign in mode';
    final toggleSemantics = _createAccountMode
        ? 'Switch to sign in'
        : 'Switch to create account';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF06151B),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Semantics(
                  label: titleSemantics,
                  child: Text(
                    title,
                    key: const ValueKey<String>('qa.auth.mode.title'),
                    style: const TextStyle(
                      color: Color(0xFFE9F2F4),
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  button: true,
                  label: toggleSemantics,
                  child: TextButton(
                    key: const ValueKey<String>('qa.auth.mode.toggle'),
                    onPressed: () {
                      setState(() {
                        _createAccountMode = !_createAccountMode;
                      });
                    },
                    child: Text(toggleText),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
