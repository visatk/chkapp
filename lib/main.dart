import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }
  runApp(const MockCheckerApp());
}

class MockCheckerApp extends StatelessWidget {
  const MockCheckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mock Card Checker Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blueGrey,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

// -----------------------------------------------------------------------------
// AUTHENTICATION WRAPPER
// -----------------------------------------------------------------------------
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const MainDashboard();
        }
        return const LoginScreen();
      },
    );
  }
}

// -----------------------------------------------------------------------------
// AUTHENTICATION SCREENS
// -----------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.redAccent));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.security, size: 80, color: Colors.blueAccent),
                const SizedBox(height: 24),
                const Text(
                  'Edge Checker Login',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  icon: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.login),
                  label: const Text('Sign in with Google'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                  ),
                  onPressed: _isLoading ? null : _signInWithGoogle,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Secure OAuth 2.0 Identity Verification via Google Identity Platform.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// MAIN DASHBOARD (NAVIGATION)
// -----------------------------------------------------------------------------
class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const CheckerScreen(),
    const HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edge Checker Pro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await GoogleSignIn().signOut();
              await FirebaseAuth.instance.signOut();
            },
          )
        ],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.check_circle_outline), label: 'Checker'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// MODELS & CLOUDFLARE API
// -----------------------------------------------------------------------------
enum CardStatus { live, dead, unknown }

class CardResult {
  final String cardData;
  final CardStatus status;
  final String message;
  final DateTime checkedAt;

  CardResult({
    required this.cardData,
    required this.status,
    required this.message,
    required this.checkedAt,
  });
}

class CloudflareCheckerAPI {
  // IMPORTANT: 
  // For local testing use: 'http://127.0.0.1:8787'
  // For production use: 'https://checker-api.<YOUR-WORKER-SUBDOMAIN>.workers.dev'
  static const String baseUrl = 'http://127.0.0.1:8787'; 
  
  static const String workerUrl = '$baseUrl/api/check';
  static const String resetUrl = '$baseUrl/api/auth/reset';

  // Explicitly call the login endpoint on the worker to force a fresh session
  static Future<bool> resetSession() async {
    try {
      final response = await http.post(Uri.parse(resetUrl));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Failed to reset session: $e');
      return false;
    }
  }

  static Future<CardResult> checkCard(String cardData) async {
    try {
      final response = await http.post(
        Uri.parse(workerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'cclist': cardData}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        CardStatus status = CardStatus.unknown;
        if (data['status'] == 'live') status = CardStatus.live;
        if (data['status'] == 'dead') status = CardStatus.dead;

        return CardResult(
          cardData: cardData,
          status: status,
          message: data['message'] ?? 'No message',
          checkedAt: DateTime.now(),
        );
      } else {
        return CardResult(
          cardData: cardData,
          status: CardStatus.unknown,
          message: 'API Error: ${response.statusCode} - ${response.body}',
          checkedAt: DateTime.now(),
        );
      }
    } catch (e) {
      return CardResult(
        cardData: cardData,
        status: CardStatus.unknown,
        message: 'Network Error: $e',
        checkedAt: DateTime.now(),
      );
    }
  }
}

// -----------------------------------------------------------------------------
// CHECKER SCREEN
// -----------------------------------------------------------------------------
class CheckerScreen extends StatefulWidget {
  const CheckerScreen({super.key});

  @override
  State<CheckerScreen> createState() => _CheckerScreenState();
}

class _CheckerScreenState extends State<CheckerScreen> {
  final TextEditingController _inputController = TextEditingController();
  
  bool _isRunning = false;
  bool _isResetting = false;
  int _total = 0;
  int _checked = 0;
  int _live = 0;
  int _dead = 0;
  int _unknown = 0;

  final List<CardResult> _results = [];
  CancellationToken? _cancellationToken;

  @override
  void dispose() {
    _inputController.dispose();
    _cancellationToken?.cancel();
    super.dispose();
  }

  Future<void> _resetWorkerSession() async {
    setState(() => _isResetting = true);
    final success = await CloudflareCheckerAPI.resetSession();
    if (mounted) {
      setState(() => _isResetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Session refreshed successfully' : 'Failed to refresh session'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _startChecker() async {
    final lines = _inputController.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (lines.isEmpty) return;

    setState(() {
      _isRunning = true;
      _total = lines.length;
      _checked = 0;
      _live = 0;
      _dead = 0;
      _unknown = 0;
      _results.clear();
      _cancellationToken = CancellationToken();
    });

    // Force a fresh session before starting a bulk batch to minimize failures
    await CloudflareCheckerAPI.resetSession();

    final User? user = FirebaseAuth.instance.currentUser;

    for (int i = 0; i < lines.length; i++) {
      if (_cancellationToken!.isCancelled) break;

      final result = await CloudflareCheckerAPI.checkCard(lines[i]);
      
      if (!mounted) return;

      setState(() {
        _checked++;
        _results.insert(0, result);
        if (result.status == CardStatus.live) {
          _live++;
          if (user != null) {
            FirebaseFirestore.instance.collection('users').doc(user.uid).collection('hits').add({
              'cardData': result.cardData,
              'message': result.message,
              'checkedAt': FieldValue.serverTimestamp(),
            }).catchError((e) => debugPrint('Firestore Error: $e'));
          }
        } else if (result.status == CardStatus.dead) {
          _dead++;
        } else {
          _unknown++;
        }
      });
      // 500ms delay to respect upstream rate limits and prevent session drops
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (mounted) {
      setState(() {
        _isRunning = false;
      });
    }
  }

  void _stopChecker() {
    _cancellationToken?.cancel();
    setState(() {
      _isRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Input Area
          Expanded(
            flex: 2,
            child: TextField(
              controller: _inputController,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Paste combos here... (Format: CARD|MM|YY|CVV)',
                hintStyle: TextStyle(color: Colors.white30),
              ),
              enabled: !_isRunning,
            ),
          ),
          const SizedBox(height: 16),
          
          // Controls
          Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
                  label: Text(_isRunning ? 'Stop' : 'Start Checker'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRunning ? Colors.redAccent : Colors.green,
                  ),
                  onPressed: _isRunning ? _stopChecker : _startChecker,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  icon: _isResetting 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Icon(Icons.refresh),
                  label: const Text('Reset', style: TextStyle(fontSize: 12)),
                  onPressed: (_isRunning || _isResetting) ? null : _resetWorkerSession,
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear', style: TextStyle(fontSize: 12)),
                  onPressed: _isRunning ? null : () {
                    _inputController.clear();
                    setState(() {
                      _results.clear();
                      _total = _checked = _live = _dead = _unknown = 0;
                    });
                  },
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                )
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Statistics
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatBadge(title: 'TOTAL', count: _total, color: Colors.blue),
              _StatBadge(title: 'CHECKED', count: _checked, color: Colors.orange),
              _StatBadge(title: 'LIVE', count: _live, color: Colors.green),
              _StatBadge(title: 'DEAD', count: _dead, color: Colors.red),
              _StatBadge(title: 'UNKNOWN', count: _unknown, color: Colors.grey),
            ],
          ),
          
          const SizedBox(height: 16),
          if (_isRunning) LinearProgressIndicator(value: _total > 0 ? _checked / _total : 0),
          const SizedBox(height: 16),
          
          // Results List
          const Text('Live Results', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Divider(),
          Expanded(
            flex: 3,
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final res = _results[index];
                Color statusColor;
                IconData statusIcon;
                
                switch (res.status) {
                  case CardStatus.live:
                    statusColor = Colors.greenAccent;
                    statusIcon = Icons.check_circle;
                    break;
                  case CardStatus.dead:
                    statusColor = Colors.redAccent;
                    statusIcon = Icons.cancel;
                    break;
                  case CardStatus.unknown:
                  default:
                    statusColor = Colors.grey;
                    statusIcon = Icons.help_outline;
                }

                return Card(
                  color: const Color(0xFF2C2C2C),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(statusIcon, color: statusColor),
                    title: Text(res.cardData, style: const TextStyle(fontFamily: 'monospace')),
                    subtitle: Text(res.message, style: TextStyle(color: statusColor, fontSize: 12)),
                    dense: true,
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

class CancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;
  void cancel() => _isCancelled = true;
}

class _StatBadge extends StatelessWidget {
  final String title;
  final int count;
  final Color color;

  const _StatBadge({required this.title, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// HISTORY SCREEN
// -----------------------------------------------------------------------------
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('hits')
          .orderBy('checkedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        
        final docs = snapshot.data?.docs ?? [];
        
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No Live hits found yet.\nStart checking to see history!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final cardData = data['cardData'] ?? 'Unknown';
            final message = data['message'] ?? '';
            final checkedAt = (data['checkedAt'] as Timestamp?)?.toDate();
            
            return Card(
              color: const Color(0xFF2C2C2C),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.star, color: Colors.greenAccent),
                title: Text(cardData, style: const TextStyle(fontFamily: 'monospace')),
                subtitle: Text(message),
                trailing: Text(
                  checkedAt != null 
                    ? '${checkedAt.month}/${checkedAt.day} ${checkedAt.hour}:${checkedAt.minute.toString().padLeft(2, '0')}'
                    : '',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            );
          },
        );
      },
    );
  }
}