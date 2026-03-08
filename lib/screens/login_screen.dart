import 'package:flutter/material.dart';
import 'package:careasy_app_mobile/utils/constants.dart';
import 'package:careasy_app_mobile/screens/register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    if (_formKey.currentState!.validate()) {
      // Ici vous ferez l'appel API avec Laravel
      print('Email: ${_emailController.text}');
      print('Password: ${_passwordController.text}');
      
      // Rediriger vers l'accueil après connexion
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connexion'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppConstants.primaryRed,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    'CE',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              // Email
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  hintText: 'Email',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer votre email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // Mot de passe
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  hintText: 'Mot de passe',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                ),
                obscureText: !_isPasswordVisible,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer votre mot de passe';
                  }
                  return null;
                },
              ),
              
              // Mot de passe oublié
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: const Text('Mot de passe oublié ?'),
                ),
              ),
              const SizedBox(height: 24),
              
              // Bouton connexion
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleLogin,
                  child: const Text('SE CONNECTER'),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Lien vers inscription
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Pas encore de compte ?'),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RegisterScreen()),
                      );
                    },
                    child: const Text('S\'inscrire'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}